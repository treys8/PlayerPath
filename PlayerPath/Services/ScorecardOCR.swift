//
//  ScorecardOCR.swift
//  PlayerPath
//
//  On-device, offline scorecard reader (SchemaV32, Phase 2). Runs Apple Vision
//  text recognition over the deskewed scan, then groups the recognized text into
//  table rows/columns by bounding-box geometry to read par + per-tee yardage for
//  each hole. The hard part is row/column grouping; it is deliberately best-effort
//  and emits PARTIAL results (nil where unsure) — the mandatory confirm grid
//  absorbs residual error and a human approves every value before it persists.
//
//  Engine: VNRecognizeTextRequest(.accurate), one universal path (iOS 17+). The
//  iOS-18 document/table API is intentionally NOT used this phase.
//
//  All output types here are TRANSIENT (not SwiftData). OUT/IN/TOTAL columns are
//  parsed into `subtotals` for a sanity cross-check ONLY — never emitted as holes.
//

import Foundation
import Vision
import UIKit
import os

nonisolated private let ocrLog = Logger(subsystem: "com.playerpath.app", category: "ScorecardOCR")

/// One hole as read off the card. Any field may be missing (partial read); the
/// confirm grid fills the gaps. `yardageByTee` maps a detected tee label
/// ("BLUE"/"WHITE"/…) to that tee's yards for this hole.
struct HoleReading: Identifiable {
    let holeNumber: Int
    var par: Int?
    var yardageByTee: [String: Int]
    var confidence: Double
    var id: Int { holeNumber }
}

/// Transient result of reading a scorecard photo.
struct ScorecardExtraction {
    var holes: [HoleReading]
    /// Tee labels detected, most-yards first (for the confirm grid's tee picker).
    var detectedTees: [String]
    var subtotals: Subtotals
    /// 0…1 — fraction of holes read, blended with mean Vision confidence. The
    /// confirm grid opens regardless; below ~0.4 it leads with "Couldn't read
    /// clearly" + Retake / Enter manually.
    var overallConfidence: Double

    /// OUT/IN/TOTAL sums, for cross-check display only — never treated as holes.
    struct Subtotals {
        var parTotal: Int?
        var yardageTotalByTee: [String: Int] = [:]
        nonisolated init() {}
    }

    nonisolated static let empty = ScorecardExtraction(holes: [], detectedTees: [], subtotals: .init(), overallConfidence: 0)
}

enum ScorecardOCR {

    /// A single recognized token placed in normalized image space. Vision's
    /// coordinate origin is bottom-left, so larger `y` = higher on the page.
    private struct Cell {
        let x: Double          // center X, 0 (left) … 1 (right)
        let y: Double          // center Y, 0 (bottom) … 1 (top)
        let text: String
        let confidence: Double
    }

    // MARK: - Public entry

    /// Reads a captured scorecard image off the main thread. Encodes to `Data`
    /// (Sendable) on the caller's actor, then decodes + recognizes inside a
    /// detached task — so no non-Sendable `UIImage`/`CGImage` crosses the
    /// boundary. Returns `.empty` when Vision finds nothing; never throws (a
    /// failed read just yields an empty confirm grid). Works fully offline.
    static func extract(from image: UIImage) async -> ScorecardExtraction {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return .empty }
        return await Task.detached(priority: .userInitiated) { () -> ScorecardExtraction in
            guard let decoded = UIImage(data: data), let cg = decoded.cgImage else { return .empty }
            let cells = recognizeCells(in: cg)
            guard !cells.isEmpty else { return .empty }
            return parse(cells: cells)
        }.value
    }

    /// Convenience: read a scorecard from a resolved local file path (e.g. to
    /// re-OCR a stored card). Returns `.empty` when the file can't be loaded.
    static func extract(fromImageAt path: String) async -> ScorecardExtraction {
        await Task.detached(priority: .userInitiated) { () -> ScorecardExtraction in
            guard let image = UIImage(contentsOfFile: path), let cg = image.cgImage else {
                ocrLog.error("Scorecard image could not be loaded at \(path, privacy: .public)")
                return .empty
            }
            let cells = recognizeCells(in: cg)
            guard !cells.isEmpty else { return .empty }
            return parse(cells: cells)
        }.value
    }

    // MARK: - Vision

    nonisolated private static func recognizeCells(in cg: CGImage) -> [Cell] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            ocrLog.error("Vision text request failed: \(error.localizedDescription)")
            return []
        }
        guard let observations = request.results else { return [] }

        var cells: [Cell] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            // An observation can hold a whole table row ("4 5 3 …") or a single
            // cell. Split on whitespace and distribute X across the bbox width so
            // either shape yields per-token cells.
            let tokens = candidate.string
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
            guard !tokens.isEmpty else { continue }
            let bb = obs.boundingBox
            let n = Double(tokens.count)
            let conf = Double(candidate.confidence)
            for (i, token) in tokens.enumerated() {
                let cx = Double(bb.minX) + Double(bb.width) * (Double(i) + 0.5) / n
                cells.append(Cell(x: cx, y: Double(bb.midY), text: token, confidence: conf))
            }
        }
        return cells
    }

    // MARK: - Parse

    nonisolated private static func parse(cells: [Cell]) -> ScorecardExtraction {
        let rows = clusterRows(cells)

        // 1. Hole-number header → column X-centers. The header row maximizes the
        //    count of integer cells in 1…18 (back-nine values 10–18 included).
        let holeColumns = detectHoleColumns(rows)
        let holeNumbers = holeColumns.keys.sorted()
        guard !holeNumbers.isEmpty else {
            // No header recognized — give the confirm grid an empty 18-hole grid.
            return ScorecardExtraction(
                holes: (1...18).map { HoleReading(holeNumber: $0, par: nil, yardageByTee: [:], confidence: 0) },
                detectedTees: [], subtotals: .init(), overallConfidence: 0
            )
        }
        let columnTolerance = halfMedianSpacing(of: holeColumns.values.sorted())

        // 2. Classify the remaining rows. Par row = mostly 3…6; yardage rows =
        //    mostly 60…700. A row can't be both.
        var parByHole: [Int: (Int, Double)] = [:]
        var yardageByTeeHole: [String: [Int: (Int, Double)]] = [:]
        var subtotals = ScorecardExtraction.Subtotals()
        var detectedTees: [String] = []
        var teeCounter = 0

        for row in rows {
            let ints = row.compactMap { cell -> (Cell, Int)? in
                guard let v = intValue(cell.text) else { return nil }
                return (cell, v)
            }
            guard !ints.isEmpty else { continue }
            // Skip the header row itself (it IS the 1…18 sequence).
            if isHeaderRow(ints, holeCount: holeNumbers.count) { continue }

            let parLike = ints.filter { (3...6).contains($0.1) }.count
            let yardageLike = ints.filter { (60...700).contains($0.1) }.count
            let rowHasParLabel = row.contains { $0.text.uppercased().hasPrefix("PAR") }
            // The par row is a STRONG majority of 3…6 values (nearly every hole).
            // A stroke-index/handicap row also holds 1…18 values — a few of which
            // fall in 3…6 — so a loose `parLike >= 3` would misclassify it as par
            // and corrupt the pars. Require a majority of the holes (or a literal
            // "PAR" label) to qualify.
            let parMajority = parLike >= yardageLike && parLike >= 4 && parLike * 2 >= holeNumbers.count

            if rowHasParLabel || parMajority {
                // Par row.
                for (cell, v) in ints where (3...6).contains(v) {
                    if let hole = nearestHole(toX: cell.x, columns: holeColumns, maxDist: columnTolerance) {
                        parByHole[hole] = (v, cell.confidence)
                    }
                }
                // Par subtotal (OUT/IN/TOTAL) — a 3…6 row's larger sums.
                subtotals.parTotal = ints.map(\.1).filter { (27...80).contains($0) }.max() ?? subtotals.parTotal
            } else if yardageLike >= 3 {
                // Yardage row → one tee.
                let label = teeLabel(for: row, fallbackIndex: teeCounter)
                teeCounter += 1
                // Dedup: two rows that resolve to the same label (e.g. both read
                // "Blue") merge into one tee — appending twice would give the
                // confirm grid's `ForEach(id: \.self)` picker duplicate IDs.
                if !detectedTees.contains(label) { detectedTees.append(label) }
                var perHole: [Int: (Int, Double)] = yardageByTeeHole[label] ?? [:]
                for (cell, v) in ints where (60...700).contains(v) {
                    if let hole = nearestHole(toX: cell.x, columns: holeColumns, maxDist: columnTolerance) {
                        perHole[hole] = (v, cell.confidence)
                    }
                }
                yardageByTeeHole[label] = perHole
                if let total = ints.map(\.1).filter({ (800...8000).contains($0) }).max() {
                    subtotals.yardageTotalByTee[label] = total
                }
            }
        }

        // 3. Assemble per-hole readings.
        var holes: [HoleReading] = []
        var confidences: [Double] = []
        var holesWithData = 0
        for hole in holeNumbers {
            var yardageByTee: [String: Int] = [:]
            var cellConfs: [Double] = []
            for (tee, perHole) in yardageByTeeHole {
                if let (yds, c) = perHole[hole] { yardageByTee[tee] = yds; cellConfs.append(c) }
            }
            let parPair = parByHole[hole]
            if let (_, c) = parPair { cellConfs.append(c) }
            let par = parPair?.0
            let hasData = par != nil || !yardageByTee.isEmpty
            if hasData { holesWithData += 1 }
            let confidence = cellConfs.isEmpty ? 0 : cellConfs.reduce(0, +) / Double(cellConfs.count)
            confidences.append(confidence)
            holes.append(HoleReading(holeNumber: hole, par: par, yardageByTee: yardageByTee, confidence: confidence))
        }

        // Order tees by total yards (longest first) so the picker reads naturally.
        let orderedTees = detectedTees.sorted {
            (subtotals.yardageTotalByTee[$0] ?? 0) > (subtotals.yardageTotalByTee[$1] ?? 0)
        }

        let meanConf = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        let readFraction = holeNumbers.isEmpty ? 0 : Double(holesWithData) / Double(holeNumbers.count)
        let overall = readFraction * (0.5 + 0.5 * meanConf)

        return ScorecardExtraction(
            holes: holes,
            detectedTees: orderedTees,
            subtotals: subtotals,
            overallConfidence: overall
        )
    }

    // MARK: - Grouping helpers

    /// Greedily clusters cells into rows by Y proximity (top to bottom).
    nonisolated private static func clusterRows(_ cells: [Cell], yTol: Double = 0.018) -> [[Cell]] {
        let sorted = cells.sorted { $0.y > $1.y }
        var rows: [[Cell]] = []
        var current: [Cell] = []
        var rowY = 0.0
        for cell in sorted {
            if current.isEmpty {
                current = [cell]; rowY = cell.y
            } else if abs(cell.y - rowY) <= yTol {
                current.append(cell)
                rowY = current.reduce(0) { $0 + $1.y } / Double(current.count)
            } else {
                rows.append(current.sorted { $0.x < $1.x })
                current = [cell]; rowY = cell.y
            }
        }
        if !current.isEmpty { rows.append(current.sorted { $0.x < $1.x }) }
        return rows
    }

    /// Finds the hole-number header row (max integer cells in 1…18) and returns
    /// `holeNumber → center X`. Uses each cell's own value as the hole number, so
    /// OUT/IN gaps don't shift the mapping.
    nonisolated private static func detectHoleColumns(_ rows: [[Cell]]) -> [Int: Double] {
        var best: [Int: Double] = [:]
        for row in rows {
            var columns: [Int: Double] = [:]
            for cell in row {
                if let v = intValue(cell.text), (1...18).contains(v), columns[v] == nil {
                    columns[v] = cell.x
                }
            }
            // Require a "1" anchor and at least 5 holes to count as a header.
            if columns[1] != nil, columns.count >= 5, columns.count > best.count {
                best = columns
            }
        }
        return best
    }

    nonisolated private static func isHeaderRow(_ ints: [(Cell, Int)], holeCount: Int) -> Bool {
        let inRange = ints.filter { (1...18).contains($0.1) }
        // A header row is dominated by 1…18 values and contains the "1" anchor.
        return inRange.count >= max(5, holeCount / 2) && inRange.contains { $0.1 == 1 }
    }

    nonisolated private static func nearestHole(toX x: Double, columns: [Int: Double], maxDist: Double) -> Int? {
        var best: Int?
        var bestD = maxDist
        for (hole, cx) in columns {
            let d = abs(cx - x)
            if d < bestD { bestD = d; best = hole }
        }
        return best
    }

    /// Half the median gap between adjacent hole columns — the match radius for
    /// assigning a value cell to a hole. Falls back to a wide-ish default.
    nonisolated private static func halfMedianSpacing(of xs: [Double]) -> Double {
        guard xs.count >= 2 else { return 0.03 }
        let gaps = zip(xs.dropFirst(), xs).map { $0 - $1 }.sorted()
        let median = gaps[gaps.count / 2]
        return max(0.01, median / 2)
    }

    /// Tee label for a yardage row: first non-numeric token (e.g. "BLUE"), else a
    /// recognized color word anywhere in the row, else "Tee N".
    nonisolated private static func teeLabel(for row: [Cell], fallbackIndex: Int) -> String {
        let colors = ["BLACK", "BLUE", "WHITE", "GOLD", "YELLOW", "RED", "GREEN", "SILVER", "GRAY", "GREY", "ORANGE", "PURPLE"]
        for cell in row {
            let upper = cell.text.uppercased().trimmingCharacters(in: .punctuationCharacters)
            if colors.contains(upper) { return upper.capitalized }
        }
        if let alpha = row.first(where: { $0.text.first?.isLetter == true && intValue($0.text) == nil }) {
            let cleaned = alpha.text.trimmingCharacters(in: .punctuationCharacters)
            if cleaned.count >= 2 { return cleaned.capitalized }
        }
        return "Tee \(fallbackIndex + 1)"
    }

    /// Parses a token to a small integer, tolerating stray non-digits. Rejects
    /// anything over 4 digits (not a hole/par/yardage value).
    nonisolated private static func intValue(_ s: String) -> Int? {
        let digits = s.filter { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 4 else { return nil }
        return Int(digits)
    }
}
