//
//  ScorecardConfirmGrid.swift
//  PlayerPath
//
//  The MANDATORY, non-bypassable confirm step for a scanned scorecard (SchemaV32,
//  Phase 2). OCR only ever *proposes*; nothing reaches a round without a human
//  approving it here. The grid pre-fills par + per-tee yardage from the scan,
//  flags low-confidence cells amber (advisory — never blocks Apply), lets the
//  user pick the tee played and (for 9-hole rounds) which nine, and edits every
//  cell. On Apply it hands a confirmed `[ScannedHole]` + tee back to the caller,
//  which decides whether to persist now (detail) or after Save (creation).
//
//  It is an INPUT grid — distinct from the read-only `GolfScorecardView`. Chip
//  styling is inline (the shared `GolfControlChip` is file-private to
//  ShotByShotContent and intentionally not promoted this phase).
//

import SwiftUI

struct ScorecardConfirmGrid: View {
    /// The OCR proposal. May be partial / empty (then it's just a manual grid).
    let extraction: ScorecardExtraction
    /// Holes in the round (9 or 18) — bounds the grid and the front/back choice.
    let holeCount: Int
    /// Current round values for pre-fill on a re-scan (par/yardage already set),
    /// used only where the scan didn't read a value. Empty for a fresh round.
    let existingByHole: [Int: (par: Int?, yardage: Int?)]
    let onCancel: () -> Void
    /// Confirmed card + chosen tee (nil when the card had no tee labels).
    let onApply: ([GolfScoreWriter.ScannedHole], String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var rows: [Row] = []
    @State private var selectedTee: String = ""
    @State private var nineIsFront = true
    @State private var editTarget: EditTarget?
    @State private var didSeed = false

    // MARK: Row model

    private struct Row: Identifiable {
        let id: Int          // hole number
        var holeNumber: Int
        var par: Int?
        var yardage: Int?
        var confidence: Double
        var edited = false

        /// Amber when the scan is unsure or a value is out of range — advisory
        /// only. Clears once the user touches the row.
        var needsCheck: Bool {
            if edited { return false }
            let parBad = par == nil || !(3...6).contains(par!)
            let ydsBad = yardage != nil && !(60...700).contains(yardage!)
            return parBad || ydsBad || confidence < 0.6
        }
    }

    private struct EditTarget: Identifiable { let id: Int }   // id = row index

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    teeAndNinePickers
                    if amberCount > 0 { checkBanner }
                    Section {
                        ForEach(rows.indices, id: \.self) { i in
                            gridRow(i)
                            Divider().opacity(0.4)
                        }
                        crossCheckFooter
                    } header: {
                        gridHeader
                    }
                }
                .padding(.horizontal)
            }
            .ppDetailBackground()
            .navigationTitle("Confirm scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Looks good, apply") { apply() }
                        .fontWeight(.semibold)
                        .tint(Theme.golfAccent)
                }
            }
            .sheet(item: $editTarget) { target in
                YardagePickerSheet(
                    distance: Binding(
                        get: { rows.indices.contains(target.id) ? rows[target.id].yardage : nil },
                        set: { newValue in
                            guard rows.indices.contains(target.id) else { return }
                            rows[target.id].yardage = newValue
                            rows[target.id].edited = true
                        }
                    ),
                    defaultCenter: defaultYardageCenter(forPar: rows.indices.contains(target.id) ? rows[target.id].par : nil)
                )
            }
            .onAppear(perform: seedIfNeeded)
            .onChange(of: selectedTee) { _, _ in reseed() }
            .onChange(of: nineIsFront) { _, _ in reseed() }
        }
    }

    // MARK: Subviews

    @ViewBuilder private var teeAndNinePickers: some View {
        VStack(spacing: 12) {
            if extraction.detectedTees.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tee played").font(.labelMedium).foregroundColor(.secondary)
                    Picker("Tee", selection: $selectedTee) {
                        ForEach(extraction.detectedTees, id: \.self) { tee in
                            Text(teeMenuLabel(tee)).tag(tee)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.golfAccent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if holeCount <= 9 {
                Picker("Which nine", selection: $nineIsFront) {
                    Text("Front 9").tag(true)
                    Text("Back 9").tag(false)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 8)
    }

    private var checkBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.warning)
            Text("\(amberCount) hole\(amberCount == 1 ? "" : "s") need a quick check")
                .font(.bodySmall)
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.12)))
        .padding(.bottom, 8)
    }

    private var gridHeader: some View {
        HStack {
            Text("Hole").frame(width: 52, alignment: .leading)
            Text("Par").frame(maxWidth: .infinity, alignment: .leading)
            Text("Yardage").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.labelMedium).foregroundColor(.secondary)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func gridRow(_ i: Int) -> some View {
        let row = rows[i]
        return HStack {
            HStack(spacing: 4) {
                if row.needsCheck {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundColor(Theme.warning)
                }
                Text("\(row.holeNumber)").font(.bodyMedium).fontWeight(.semibold)
            }
            .frame(width: 52, alignment: .leading)

            // Par — Menu 3…6
            Menu {
                ForEach(3...6, id: \.self) { p in
                    Button("Par \(p)") { rows[i].par = p; rows[i].edited = true }
                }
            } label: {
                chip(text: row.par.map { "Par \($0)" } ?? "Set par",
                     set: row.par != nil, amber: row.needsCheck && (row.par == nil || !(3...6).contains(row.par!)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Yardage — wheel sheet
            Button {
                editTarget = EditTarget(id: i)
            } label: {
                chip(text: row.yardage.map { "\($0) yds" } ?? "Add yardage",
                     set: row.yardage != nil,
                     amber: row.needsCheck && row.yardage != nil && !(60...700).contains(row.yardage!),
                     systemImage: "ruler")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hole \(row.holeNumber)")
        .accessibilityValue("par \(row.par.map(String.init) ?? "not set"), \(row.yardage.map { "\($0) yards" } ?? "yardage not set")\(row.needsCheck ? ", please check" : "")")
    }

    @ViewBuilder private var crossCheckFooter: some View {
        let parSum = rows.compactMap(\.par).reduce(0, +)
        let ydsSum = rows.compactMap(\.yardage).reduce(0, +)
        VStack(alignment: .leading, spacing: 4) {
            crossCheckLine(label: "Par total", computed: parSum, card: extraction.subtotals.parTotal)
            crossCheckLine(label: "Yardage total", computed: ydsSum,
                           card: selectedTee.isEmpty ? nil : extraction.subtotals.yardageTotalByTee[selectedTee])
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }

    private func crossCheckLine(label: String, computed: Int, card: Int?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(computed)").monospacedDigit()
            if let card, card != computed {
                Text("(card \(card))").foregroundColor(Theme.warning)
            }
        }
    }

    // MARK: Inline chip

    private func chip(text: String, set: Bool, amber: Bool, systemImage: String? = nil) -> some View {
        let tint: Color = amber ? Theme.warning : (set ? Theme.golfAccent : .secondary)
        return HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.caption) }
            Text(text).font(.bodySmall).fontWeight(.medium).monospacedDigit()
        }
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    // MARK: Seeding

    private func seedIfNeeded() {
        guard !didSeed else { return }
        didSeed = true
        if selectedTee.isEmpty { selectedTee = extraction.detectedTees.first ?? "" }
        reseed()
    }

    /// Rebuilds the editable rows from the extraction + existing fallback for the
    /// current tee / nine. Picking the tee first (it's at the top) is the
    /// expected flow, so rebuilding here is fine.
    private func reseed() {
        let displayed = displayedHoleNumbers
        // Decide mapping ONCE for the whole grid, not per hole: if any displayed
        // hole number matches a read hole number, map strictly by number (a gap
        // in the OCR'd numbers must leave that hole blank, never borrow the i-th
        // reading — which would misassign every hole after the gap). Only when
        // NOTHING matches (e.g. a back-nine round seeded from a card numbered
        // 1–9) do we fall back to a positional, whole-set map.
        let matchByNumber = displayed.contains { hole in
            extraction.holes.contains { $0.holeNumber == hole }
        }
        rows = displayed.enumerated().map { (i, hole) in
            let reading: HoleReading? = matchByNumber
                ? extraction.holes.first { $0.holeNumber == hole }
                : (i < extraction.holes.count ? extraction.holes[i] : nil)
            let existing = existingByHole[hole]
            let scanYards: Int? = {
                guard let reading else { return nil }
                if !selectedTee.isEmpty { return reading.yardageByTee[selectedTee] }
                return reading.yardageByTee.values.first
            }()
            return Row(
                id: hole,
                holeNumber: hole,
                par: reading?.par ?? existing?.par,
                yardage: scanYards ?? existing?.yardage,
                confidence: reading?.confidence ?? 0
            )
        }
    }

    private var displayedHoleNumbers: [Int] {
        if holeCount <= 9 {
            return Array((nineIsFront ? 1 : 10)...(nineIsFront ? 9 : 18))
        }
        return Array(1...18)
    }

    // MARK: Apply

    private func apply() {
        // Only holes with a confirmed par become card entries — we never invent a
        // par. Yardage stays optional. Holes left blank simply aren't pre-filled.
        let holes: [GolfScoreWriter.ScannedHole] = rows.compactMap { row in
            guard let par = row.par else { return nil }
            return GolfScoreWriter.ScannedHole(hole: row.holeNumber, par: par, yardage: row.yardage)
        }
        Haptics.success()
        onApply(holes, selectedTee.isEmpty ? nil : selectedTee)
        dismiss()
    }

    // MARK: Helpers

    private func teeMenuLabel(_ tee: String) -> String {
        if let total = extraction.subtotals.yardageTotalByTee[tee] {
            return "\(tee) — \(total.formatted()) yds"
        }
        return tee
    }

    private var amberCount: Int { rows.filter(\.needsCheck).count }

    private func defaultYardageCenter(forPar par: Int?) -> Int {
        switch par {
        case 3: return 165
        case 5: return 530
        default: return 400
        }
    }
}
