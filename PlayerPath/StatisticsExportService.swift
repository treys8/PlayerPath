//
//  StatisticsExportService.swift
//  PlayerPath
//
//  Service for exporting athlete statistics to CSV and PDF formats
//

import Foundation
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Service to export athlete statistics to various formats
final class StatisticsExportService {

    // MARK: - Public Export Methods

    /// Export statistics to CSV format (requires Plus tier or higher)
    static func exportToCSV(athlete: Athlete, stats: AthleteStatistics) -> Result<URL, ExportError> {
        guard SubscriptionGate.effectiveAthleteTier >= .plus else {
            return .failure(.fileCreationFailed("Statistics export requires a Plus or Pro subscription."))
        }

        let csvContent = generateCSVContent(athlete: athlete, stats: stats)

        do {
            let fileName = "\(athlete.name.replacingOccurrences(of: " ", with: "_"))_Stats_\(dateString()).csv"
            let fileURL = try saveToTemporaryFile(content: csvContent, fileName: fileName)
            return .success(fileURL)
        } catch {
            return .failure(.fileCreationFailed(error.localizedDescription))
        }
    }

    /// Export statistics to PDF format with formatted layout (requires Plus tier or higher)
    static func exportToPDF(athlete: Athlete, stats: AthleteStatistics, season: Season? = nil) -> Result<URL, ExportError> {
        guard SubscriptionGate.effectiveAthleteTier >= .plus else {
            return .failure(.fileCreationFailed("Statistics export requires a Plus or Pro subscription."))
        }

        let pdfData = generatePDFData(athlete: athlete, stats: stats, season: season)

        do {
            let fileName = "\(athlete.name.replacingOccurrences(of: " ", with: "_"))_Stats_\(dateString()).pdf"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try pdfData.write(to: fileURL)
            return .success(fileURL)
        } catch {
            return .failure(.fileCreationFailed(error.localizedDescription))
        }
    }

    // MARK: - CSV Generation

    private static func generateCSVContent(athlete: Athlete, stats: AthleteStatistics) -> String {
        var csv = ""

        // Header
        csv += "PlayerPath Statistics Export\n"
        csv += "Generated: \(Date().formatted(date: .long, time: .shortened))\n"
        csv += "\n"

        // Athlete Info
        csv += "Athlete Information\n"
        csv += "Name,\(escapeCSV(athlete.name))\n"
        csv += "Created,\(escapeCSV(athlete.createdAt?.formatted(date: .long, time: .omitted) ?? "N/A"))\n"
        csv += "\n"

        // Season Info (if active season)
        if let season = athlete.activeSeason {
            csv += "Active Season\n"
            csv += "Season Name,\(escapeCSV(season.displayName))\n"
            csv += "Sport,\(escapeCSV((season.sport ?? .baseball).displayName))\n"
            csv += "Start Date,\(escapeCSV(season.startDate?.formatted(date: .long, time: .omitted) ?? "N/A"))\n"
            csv += "\n"
        }

        // Key Statistics
        csv += "Key Statistics\n"
        csv += "Metric,Value\n"
        csv += "Total Games,\(stats.totalGames)\n"
        csv += "At Bats,\(stats.atBats)\n"
        csv += "Hits,\(stats.hits)\n"
        csv += "Batting Average,\(String(format: "%.3f", stats.battingAverage))\n"
        csv += "On-Base Percentage,\(String(format: "%.3f", stats.onBasePercentage))\n"
        csv += "Slugging Percentage,\(String(format: "%.3f", stats.sluggingPercentage))\n"
        csv += "OPS,\(String(format: "%.3f", stats.onBasePercentage + stats.sluggingPercentage))\n"
        csv += "\n"

        // Hitting Breakdown
        csv += "Hitting Breakdown\n"
        csv += "Type,Count\n"
        csv += "Singles,\(stats.singles)\n"
        csv += "Doubles,\(stats.doubles)\n"
        csv += "Triples,\(stats.triples)\n"
        csv += "Home Runs,\(stats.homeRuns)\n"
        csv += "Walks,\(stats.walks)\n"
        csv += "\n"

        // Other Stats
        csv += "Other Statistics\n"
        csv += "Metric,Value\n"
        csv += "Runs,\(stats.runs)\n"
        csv += "RBIs,\(stats.rbis)\n"
        csv += "Strikeouts,\(stats.strikeouts)\n"
        csv += "Ground Outs,\(stats.groundOuts)\n"
        csv += "Fly Outs,\(stats.flyOuts)\n"
        csv += "\n"

        // Games Breakdown (if available)
        if let games = athlete.games?.filter({ $0.isComplete }), !games.isEmpty {
            csv += "Recent Games\n"
            csv += "Date,Opponent,Result\n"

            for game in games.prefix(10).sorted(by: { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }) {
                // Abbreviated dates contain a comma ("Jun 10, 2026") — escape so
                // the column doesn't split.
                let dateStr = game.date?.formatted(date: .abbreviated, time: .omitted) ?? "N/A"
                let opponent = escapeCSV(game.opponent.isEmpty ? "Unknown" : game.opponent)
                csv += "\(escapeCSV(dateStr)),\(opponent),Completed\n"
            }
        }

        return csv
    }

    // MARK: - PDF Generation

    private static func generatePDFData(athlete: Athlete, stats: AthleteStatistics, season: Season?) -> Data {
        let pageWidth: CGFloat = 612 // 8.5 inches
        let pageHeight: CGFloat = 792 // 11 inches
        let margin: CGFloat = 50

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()

            var yPosition: CGFloat = margin
            let contentWidth = pageWidth - (2 * margin)

            // Title
            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let titleText = "PlayerPath Statistics Report"
            let titleRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: 30)
            titleText.draw(in: titleRect, withAttributes: [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ])
            yPosition += 40

            // Athlete Name
            let nameFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
            let nameText = athlete.name
            let nameRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: 25)
            nameText.draw(in: nameRect, withAttributes: [
                .font: nameFont,
                .foregroundColor: UIColor.darkGray
            ])
            yPosition += 35

            // Generated Date
            let dateFont = UIFont.systemFont(ofSize: 10)
            let dateText = "Generated: \(Date().formatted(date: .long, time: .shortened))"
            let dateRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: 15)
            dateText.draw(in: dateRect, withAttributes: [
                .font: dateFont,
                .foregroundColor: UIColor.gray
            ])
            yPosition += 25

            // Separator line
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: yPosition))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
            UIColor.lightGray.setStroke()
            path.lineWidth = 1
            path.stroke()
            yPosition += 20

            // Season Info (if available)
            if let season = season ?? athlete.activeSeason {
                yPosition = drawSection(
                    title: "Season Information",
                    items: [
                        ("Season", season.displayName),
                        ("Sport", (season.sport ?? .baseball).displayName),
                        ("Start Date", season.startDate?.formatted(date: .long, time: .omitted) ?? "N/A"),
                        ("Games", "\(season.completedGames)")
                    ],
                    yPosition: yPosition,
                    margin: margin,
                    contentWidth: contentWidth
                )
            }

            // Key Statistics Section
            yPosition = drawSection(
                title: "Key Statistics",
                items: [
                    ("Total Games", "\(stats.totalGames)"),
                    ("At Bats", "\(stats.atBats)"),
                    ("Hits", "\(stats.hits)"),
                    ("Batting Average", String(format: "%.3f", stats.battingAverage)),
                    ("On-Base %", String(format: "%.3f", stats.onBasePercentage)),
                    ("Slugging %", String(format: "%.3f", stats.sluggingPercentage)),
                    ("OPS", String(format: "%.3f", stats.onBasePercentage + stats.sluggingPercentage))
                ],
                yPosition: yPosition,
                margin: margin,
                contentWidth: contentWidth
            )

            // Hitting Breakdown
            yPosition = drawSection(
                title: "Hitting Breakdown",
                items: [
                    ("Singles", "\(stats.singles)"),
                    ("Doubles", "\(stats.doubles)"),
                    ("Triples", "\(stats.triples)"),
                    ("Home Runs", "\(stats.homeRuns)"),
                    ("Walks", "\(stats.walks)")
                ],
                yPosition: yPosition,
                margin: margin,
                contentWidth: contentWidth
            )

            // Other Statistics
            yPosition = drawSection(
                title: "Other Statistics",
                items: [
                    ("Runs", "\(stats.runs)"),
                    ("RBIs", "\(stats.rbis)"),
                    ("Strikeouts", "\(stats.strikeouts)"),
                    ("Ground Outs", "\(stats.groundOuts)"),
                    ("Fly Outs", "\(stats.flyOuts)")
                ],
                yPosition: yPosition,
                margin: margin,
                contentWidth: contentWidth
            )

            // Footer
            let footerFont = UIFont.systemFont(ofSize: 9)
            let footerText = "Generated with PlayerPath • playerpath.net"
            let footerRect = CGRect(x: margin, y: pageHeight - margin, width: contentWidth, height: 15)
            footerText.draw(in: footerRect, withAttributes: [
                .font: footerFont,
                .foregroundColor: UIColor.lightGray
            ])
        }

        return data
    }

    @discardableResult
    private static func drawSection(title: String, items: [(String, String)], yPosition: CGFloat, margin: CGFloat, contentWidth: CGFloat) -> CGFloat {
        var y = yPosition

        // Section title
        let titleFont = UIFont.boldSystemFont(ofSize: 16)
        let titleRect = CGRect(x: margin, y: y, width: contentWidth, height: 20)
        title.draw(in: titleRect, withAttributes: [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ])
        y += 25

        // Items
        let itemFont = UIFont.systemFont(ofSize: 12)
        let labelWidth = contentWidth * 0.5
        let valueWidth = contentWidth * 0.5

        for (label, value) in items {
            let labelRect = CGRect(x: margin, y: y, width: labelWidth, height: 18)
            label.draw(in: labelRect, withAttributes: [
                .font: itemFont,
                .foregroundColor: UIColor.darkGray
            ])

            let valueRect = CGRect(x: margin + labelWidth, y: y, width: valueWidth, height: 18)
            value.draw(in: valueRect, withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ])

            y += 20
        }

        y += 10
        return y
    }

    // MARK: - Helper Methods

    /// Wraps a CSV field in quotes if it contains commas, quotes, or newlines,
    /// and escapes internal double-quotes per RFC 4180.
    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func saveToTemporaryFile(content: String, fileName: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Golf Export
    //
    // Golf has no AthleteStatistics model — everything derives live from
    // GolfExportData / HandicapEstimator (hence @MainActor for model + handicap
    // access). Reuses the shared CSV/PDF helpers above.

    @MainActor
    static func exportGolfToCSV(athlete: Athlete, season: Season?) -> Result<URL, ExportError> {
        guard SubscriptionGate.effectiveAthleteTier >= .plus else {
            return .failure(.fileCreationFailed("Statistics export requires a Plus or Pro subscription."))
        }
        let csv = generateGolfCSV(athlete: athlete, season: season)
        do {
            let fileName = "\(athlete.name.replacingOccurrences(of: " ", with: "_"))_Golf_\(dateString()).csv"
            let url = try saveToTemporaryFile(content: csv, fileName: fileName)
            return .success(url)
        } catch {
            return .failure(.fileCreationFailed(error.localizedDescription))
        }
    }

    @MainActor
    static func exportGolfToPDF(athlete: Athlete, season: Season?) -> Result<URL, ExportError> {
        guard SubscriptionGate.effectiveAthleteTier >= .plus else {
            return .failure(.fileCreationFailed("Statistics export requires a Plus or Pro subscription."))
        }
        let data = generateGolfPDFData(athlete: athlete, season: season)
        do {
            let fileName = "\(athlete.name.replacingOccurrences(of: " ", with: "_"))_Golf_\(dateString()).pdf"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url)
            return .success(url)
        } catch {
            return .failure(.fileCreationFailed(error.localizedDescription))
        }
    }

    // MARK: - Golf CSV

    @MainActor
    private static func generateGolfCSV(athlete: Athlete, season: Season?) -> String {
        let summary = GolfExportData.summary(for: athlete, season: season)
        let adv = GolfExportData.advancedStats(for: athlete, season: season)
        let tournament = GolfExportData.tournamentRounds(for: athlete, season: season)
        let practice = GolfExportData.practiceRounds(for: athlete, season: season)
        let handicap = HandicapEstimator.estimatedIndex(for: athlete, season: season)

        var csv = "PlayerPath Golf Statistics Export\n"
        csv += "Generated: \(Date().formatted(date: .long, time: .shortened))\n\n"
        csv += "Athlete,\(escapeCSV(athlete.name))\n"
        if let season { csv += "Season,\(escapeCSV(season.displayName))\n" }
        csv += "\n"

        csv += "Summary\nMetric,Value\n"
        csv += "Rounds,\(summary.totalRounds)\n"
        if let b = summary.bestScore { csv += "Best Score,\(b)\n" }
        if let w = summary.worstScore { csv += "Worst Score,\(w)\n" }
        if let a = summary.tournamentAverage { csv += "Tournament Avg,\(String(format: "%.1f", a))\n" }
        if let p = summary.practiceAverage { csv += "Practice Avg,\(String(format: "%.1f", p))\n" }
        if let h = handicap { csv += "Est. Handicap,\(golfToParStr(h, asHandicap: true))\n" }
        if let atp = adv.avgToPar { csv += "Avg To Par,\(golfToParStr(atp))\n" }
        csv += "\n"

        csv += "Detailed\nMetric,Value\n"
        if let g = adv.girPct { csv += "GIR %,\(Int(g.rounded()))\n" }
        if let f = adv.firPct { csv += "Fairways %,\(Int(f.rounded()))\n" }
        if let pr = adv.puttsPerRound { csv += "Putts per Round,\(String(format: "%.1f", pr))\n" }
        if let pg = adv.puttsPerGIR { csv += "Putts per GIR,\(String(format: "%.2f", pg))\n" }
        if let sc = adv.scramblingPct { csv += "Scrambling %,\(Int(sc.rounded()))\n" }
        if let pen = adv.penaltiesPerRound { csv += "Penalties per Round,\(String(format: "%.1f", pen))\n" }
        if let p3 = adv.par3Avg { csv += "Par 3 Avg,\(String(format: "%.2f", p3))\n" }
        if let p4 = adv.par4Avg { csv += "Par 4 Avg,\(String(format: "%.2f", p4))\n" }
        if let p5 = adv.par5Avg { csv += "Par 5 Avg,\(String(format: "%.2f", p5))\n" }
        csv += "\n"

        csv += "Rounds\nDate,Course,Type,Holes,Par,Score,To Par,Putts,GIR %,Fairways %\n"
        for r in tournament { csv += golfRoundCSVLine(r, type: "Tournament") }
        for r in practice { csv += golfRoundCSVLine(r, type: "Practice") }

        return csv
    }

    private static func golfRoundCSVLine(_ r: GolfRoundRow, type: String) -> String {
        // Abbreviated dates contain a comma ("Jun 10, 2026") — escape so the
        // column doesn't split.
        let date = r.date?.formatted(date: .abbreviated, time: .omitted) ?? "N/A"
        let par = r.par.map(String.init) ?? ""
        let score = r.score.map(String.init) ?? ""
        let putts = r.putts.map(String.init) ?? ""
        let gir = r.girPct.map { "\(Int($0.rounded()))" } ?? ""
        let fir = r.firPct.map { "\(Int($0.rounded()))" } ?? ""
        return "\(escapeCSV(date)),\(escapeCSV(r.course)),\(type),\(r.holes),\(par),\(score),\(r.toParString),\(putts),\(gir),\(fir)\n"
    }

    // MARK: - Golf PDF

    @MainActor
    private static func generateGolfPDFData(athlete: Athlete, season: Season?) -> Data {
        let summary = GolfExportData.summary(for: athlete, season: season)
        let adv = GolfExportData.advancedStats(for: athlete, season: season)
        let handicap = HandicapEstimator.estimatedIndex(for: athlete, season: season)
        let tournament = GolfExportData.tournamentRounds(for: athlete, season: season)
        let practice = GolfExportData.practiceRounds(for: athlete, season: season)
        let recent = (tournament + practice)
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .prefix(12)

        let pageWidth: CGFloat = 612, pageHeight: CGFloat = 792, margin: CGFloat = 50
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin
            let contentWidth = pageWidth - (2 * margin)

            "PlayerPath Golf Report".draw(in: CGRect(x: margin, y: y, width: contentWidth, height: 30),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24), .foregroundColor: UIColor.black])
            y += 40
            athlete.name.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: 25),
                withAttributes: [.font: UIFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: UIColor.darkGray])
            y += 35
            "Generated: \(Date().formatted(date: .long, time: .shortened))".draw(in: CGRect(x: margin, y: y, width: contentWidth, height: 15),
                withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.gray])
            y += 25

            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            UIColor.lightGray.setStroke(); path.lineWidth = 1; path.stroke()
            y += 20

            if let season = season ?? athlete.activeSeason {
                y = drawSection(title: "Season", items: [
                    ("Season", season.displayName),
                    ("Sport", (season.sport ?? .baseball).displayName)
                ], yPosition: y, margin: margin, contentWidth: contentWidth)
            }

            var summaryItems: [(String, String)] = [("Rounds", "\(summary.totalRounds)")]
            if let b = summary.bestScore { summaryItems.append(("Best Score", "\(b)")) }
            if let w = summary.worstScore { summaryItems.append(("Worst Score", "\(w)")) }
            if let a = summary.tournamentAverage { summaryItems.append(("Tournament Avg", String(format: "%.1f", a))) }
            if let p = summary.practiceAverage { summaryItems.append(("Practice Avg", String(format: "%.1f", p))) }
            if let h = handicap { summaryItems.append(("Est. Handicap", golfToParStr(h, asHandicap: true))) }
            if let atp = adv.avgToPar { summaryItems.append(("Avg To Par", golfToParStr(atp))) }
            y = drawSection(title: "Summary", items: summaryItems, yPosition: y, margin: margin, contentWidth: contentWidth)

            var detailItems: [(String, String)] = []
            if let g = adv.girPct { detailItems.append(("GIR %", "\(Int(g.rounded()))%")) }
            if let f = adv.firPct { detailItems.append(("Fairways %", "\(Int(f.rounded()))%")) }
            if let pr = adv.puttsPerRound { detailItems.append(("Putts / Round", String(format: "%.1f", pr))) }
            if let sc = adv.scramblingPct { detailItems.append(("Scrambling %", "\(Int(sc.rounded()))%")) }
            if let pen = adv.penaltiesPerRound { detailItems.append(("Penalties / Round", String(format: "%.1f", pen))) }
            if let p3 = adv.par3Avg { detailItems.append(("Par 3 Avg", String(format: "%.2f", p3))) }
            if let p4 = adv.par4Avg { detailItems.append(("Par 4 Avg", String(format: "%.2f", p4))) }
            if let p5 = adv.par5Avg { detailItems.append(("Par 5 Avg", String(format: "%.2f", p5))) }
            if !detailItems.isEmpty {
                y = drawSection(title: "Detailed", items: detailItems, yPosition: y, margin: margin, contentWidth: contentWidth)
            }

            if !recent.isEmpty {
                let roundItems: [(String, String)] = recent.map { r in
                    let date = r.date?.formatted(date: .abbreviated, time: .omitted) ?? ""
                    let label = "\(r.course)\(date.isEmpty ? "" : " · \(date)")"
                    let scoreStr = r.score.map(String.init) ?? "—"
                    return (label, "\(scoreStr) (\(r.toParString))")
                }
                y = drawSection(title: "Recent Rounds", items: roundItems, yPosition: y, margin: margin, contentWidth: contentWidth)
            }

            "Generated with PlayerPath • playerpath.net".draw(in: CGRect(x: margin, y: pageHeight - margin, width: contentWidth, height: 15),
                withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.lightGray])
        }
    }

    /// "E" / "+3" / "-2" for to-par; or handicap form ("+2.1" plus-handicap / "11.4").
    private static func golfToParStr(_ v: Double, asHandicap: Bool = false) -> String {
        let r = (v * 10).rounded() / 10
        if asHandicap {
            return r < 0 ? "+\(String(format: "%.1f", -r))" : String(format: "%.1f", r)
        }
        if abs(r) < 0.05 { return "E" }
        let body = r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
        return r > 0 ? "+\(body)" : body
    }
}

// MARK: - Export Error

enum ExportError: LocalizedError {
    case noStatistics
    case fileCreationFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noStatistics:
            return "No statistics available to export"
        case .fileCreationFailed(let reason):
            return "Failed to create export file: \(reason)"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noStatistics:
            return "Record some games first to generate statistics."
        case .fileCreationFailed:
            return "Try again or check your device storage."
        case .exportFailed:
            return "Try exporting again."
        }
    }
}
