//
//  GolfScorecardView.swift
//  PlayerPath
//
//  Full-round scorecard entry — the fast path for scoring a whole golf round on
//  one screen (vs. ScoreHoleSheet's one-hole-at-a-time flow). All holes show in
//  an OUT/IN grid up top; tapping a hole selects it and a number strip at the
//  bottom sets its score, auto-advancing to the next unscored hole. Putts are
//  optional behind a toggle. Save writes every changed hole in ONE transaction
//  through GolfScoreWriter — identical totals + birdie-reel behavior as the
//  single-hole sheet.
//
//  Detailed per-hole tracking (FIR / GIR / penalties) is layered on in PR B,
//  gated behind the global "track detailed stats" toggle; this PR is score +
//  par + optional putts only.
//

import SwiftUI
import SwiftData

struct GolfScorecardView: View {
    let round: GolfRoundRef

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// One row's in-flight values. `score == nil` means the hole isn't entered
    /// yet (shown as "·" and skipped on save). Detailed fields stay nil unless
    /// the user tracks them.
    private struct HoleEntry {
        var par: Int
        var score: Int?
        var putts: Int?
        var fairwayHit: Bool? = nil
        var greenInRegulation: Bool? = nil
        var penalties: Int? = nil
    }

    /// Opt-in detailed tracking — reveals fairway / green / penalty inputs.
    @AppStorage(GolfPrefs.trackDetailedStats) private var trackDetailed = false

    @State private var entries: [Int: HoleEntry] = [:]
    /// Holes the user actually touched — only these are written on save, so a
    /// re-open + Save doesn't re-dirty (and re-sync) every untouched hole.
    @State private var dirtyHoles: Set<Int> = []
    @State private var selectedHole: Int = 1
    /// Visibility-only: reveals the per-hole putts strip. Does NOT gate saving —
    /// each hole's putts are written from its own entry, so toggling this off
    /// never erases putts (seeded on when the round already has any).
    @State private var showPutts: Bool = false
    @State private var didLoad = false
    @State private var isSaving = false
    /// Hole picked for shot-by-shot entry — only used on shot-tracked rounds,
    /// where tapping a hole routes to ShotEntryView instead of inline editing.
    @State private var shotEntryTarget: ScoreHoleTarget?

    /// When true this round is logged shot-by-shot: the inline score editor is
    /// read-only (only ShotRollup writes these holes) and hole taps open the
    /// shot-entry card. Guards against two writers touching one HoleScore.
    private var isShotTracked: Bool { round.tracksShotByShot }

    /// A hole is owned by ShotRollup when the round is shot-tracked OR the hole
    /// already carries shots. Such holes stay read-only here and route to
    /// ShotEntryView even if `tracksShotByShot` was later turned off — so the
    /// inline editor can never two-write a shot-derived hole (plan risk #4).
    private func isHoleShotLocked(_ n: Int) -> Bool {
        isShotTracked || round.hasShots(onHole: n)
    }

    /// Whether any hole is still editable inline — drives Save vs Done.
    private var hasEditableHole: Bool {
        (1...holeCount).contains { !isHoleShotLocked($0) }
    }

    private var holeCount: Int { round.holeCount }
    private var outRange: ClosedRange<Int> { 1...min(9, holeCount) }
    private var inRange: ClosedRange<Int>? { holeCount > 9 ? 10...holeCount : nil }

    // MARK: - Totals

    private func nineTotal(_ range: ClosedRange<Int>) -> Int {
        range.compactMap { entries[$0]?.score }.reduce(0, +)
    }
    private var roundTotal: Int { (1...holeCount).compactMap { entries[$0]?.score }.reduce(0, +) }
    private var scoredParSum: Int {
        (1...holeCount).compactMap { n in entries[n]?.score != nil ? entries[n]?.par : nil }.reduce(0, +)
    }
    /// To-par over the holes scored so far (so a partial round reads sensibly).
    private var toPar: Int { roundTotal - scoredParSum }
    private var anyScored: Bool { (1...holeCount).contains { entries[$0]?.score != nil } }

    private var toParString: String {
        if toPar == 0 { return "E" }
        return toPar > 0 ? "+\(toPar)" : "\(toPar)"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .spacingLarge) {
                    summaryHeader
                    nineSection("OUT", range: outRange)
                    if let inRange { nineSection("IN", range: inRange) }
                }
                .padding(.spacingLarge)
            }
            .ppDetailBackground()
            .navigationTitle("Scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Nothing editable inline (fully shot-owned round) → a single
                    // "Done" suffices; no separate Cancel.
                    if hasEditableHole {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if hasEditableHole {
                        Button("Save") { save() }
                            .disabled(!anyScored || isSaving)
                            .fontWeight(.semibold)
                    } else {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { editorPanel }
            .sheet(item: $shotEntryTarget, onDismiss: { seedEntries() }) { target in
                // Re-seed on dismiss so the grid reflects the freshly derived
                // score / putts after logging shots. A shot-owned hole opens the
                // unified sheet locked to shot-by-shot.
                switch round {
                case .game(let g):     HoleScoringSheet(game: g, holeNumber: target.holeNumber)
                case .practice(let p): HoleScoringSheet(practice: p, holeNumber: target.holeNumber)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    // MARK: - Summary

    private var summaryHeader: some View {
        HStack {
            Text("Total")
                .font(.headingMedium)
            Spacer()
            if anyScored {
                Text("\(roundTotal)")
                    .font(.ppStatLarge)
                    .monospacedDigit()
                Text("(\(toParString))")
                    .font(.bodyMedium)
                    .monospacedDigit()
                    .foregroundColor(.parRelative(toPar))
            } else {
                Text("Tap a hole to start")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.spacingMedium)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                .fill(Theme.card)
        )
    }

    // MARK: - Nine grid

    private func nineSection(_ title: String, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: .spacingSmall) {
            HStack {
                Text(title)
                    .font(.labelMedium)
                    .foregroundColor(.secondary)
                Spacer()
                if range.contains(where: { entries[$0]?.score != nil }) {
                    Text("\(nineTotal(range))")
                        .font(.labelMedium)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: .spacingSmall)], spacing: .spacingSmall) {
                ForEach(Array(range), id: \.self) { holeCell($0) }
            }
        }
    }

    private func holeCell(_ n: Int) -> some View {
        let entry = entries[n]
        let locked = isHoleShotLocked(n)
        // A shot-owned hole shows no inline selection — tapping opens the
        // shot-entry card rather than selecting it for inline editing.
        let isSelected = !locked && n == selectedHole
        let scoreColor: Color = entry?.score == nil ? .secondary : .parRelative((entry!.score! ) - entry!.par)
        return Button {
            Haptics.light()
            if locked {
                shotEntryTarget = ScoreHoleTarget(holeNumber: n)
            } else {
                selectedHole = n
            }
        } label: {
            VStack(spacing: 1) {
                Text("\(n)")
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
                Text(entry?.score.map(String.init) ?? "·")
                    .font(.headingMedium)
                    .monospacedDigit()
                    .foregroundColor(scoreColor)
                Text("P\(entry?.par ?? 4)")
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 42, minHeight: 50)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: .cornerMedium)
                    .fill(isSelected ? Color.brandNavy.opacity(0.12) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: .cornerMedium)
                    .stroke(isSelected ? Color.brandNavy : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom editor panel (selected hole)

    @ViewBuilder
    private var editorPanel: some View {
        if isHoleShotLocked(selectedHole) {
            shotTrackedHint
        } else {
            scoreEditorPanel
        }
    }

    /// Read-only footer shown when the selected hole is shot-owned — inline
    /// editing is disabled so only ShotRollup writes it (plan risk #4: avoid
    /// two writers).
    private var shotTrackedHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope")
                .foregroundColor(Theme.golfAccent)
            Text("Tracked shot by shot. Tap a hole to log or edit its shots.")
                .font(.bodySmall)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.spacingMedium)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var scoreEditorPanel: some View {
        let entry = entries[selectedHole] ?? HoleEntry(par: 4, score: nil, putts: nil)
        return VStack(spacing: .spacingSmall) {
            // Running total — the top summary scrolls off the screen while you're
            // entering holes, so mirror it here in the pinned editor.
            if anyScored {
                HStack(spacing: 8) {
                    Text("Round Total")
                        .font(.labelSmall)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(roundTotal)")
                        .font(.bodyMedium).monospacedDigit().fontWeight(.semibold)
                    Text("(\(toParString))")
                        .font(.labelMedium).monospacedDigit()
                        .foregroundColor(.parRelative(toPar))
                }
            }

            HStack {
                Text("Hole \(selectedHole)")
                    .font(.headingMedium)
                Spacer()
                Picker("Par", selection: parBinding) {
                    ForEach(3...6, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            NumberChipGrid(range: 1...12, selected: entry.score ?? 0, par: entry.par) { value in
                setScore(value)
            }

            // Compact, equal-footing toggles so the fast path (scores only) keeps
            // the pinned panel short and both strips are equally discoverable.
            // Round-level visibility — turning a strip off never nulls a hole's
            // saved putts/detail (each hole writes from its own entry).
            HStack(spacing: .spacingSmall) {
                Toggle("Putts", isOn: $showPutts.animation())
                Toggle("Details", isOn: $trackDetailed.animation())
                Spacer()
            }
            .font(.bodyMedium)
            .toggleStyle(.button)

            if showPutts {
                NumberChipGrid(range: 0...min(10, entry.score ?? 10),
                               selected: entry.putts ?? -1,
                               par: nil) { value in
                    setPutts(value)
                }
            }

            if trackDetailed {
                if entry.par >= 4 {
                    HitMissControl(label: "Fairway", systemImage: "arrow.up.forward", value: firBinding)
                }
                HitMissControl(label: "Green in Reg.", systemImage: "flag.fill", value: girBinding)
                Stepper(value: penaltyBinding, in: 0...10) {
                    HStack {
                        Text("Penalties").font(.bodyMedium)
                        Spacer()
                        Text("\(entry.penalties ?? 0)")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.spacingMedium)
        .background(.bar)
    }

    // MARK: - Detailed-field bindings

    /// Mutates the selected hole's entry and marks it dirty.
    private func update(_ mutate: (inout HoleEntry) -> Void) {
        var e = entries[selectedHole] ?? HoleEntry(par: 4, score: nil, putts: nil)
        mutate(&e)
        entries[selectedHole] = e
        dirtyHoles.insert(selectedHole)
    }

    private var firBinding: Binding<Bool?> {
        Binding(get: { entries[selectedHole]?.fairwayHit },
                set: { v in update { $0.fairwayHit = v } })
    }
    private var girBinding: Binding<Bool?> {
        Binding(get: { entries[selectedHole]?.greenInRegulation },
                set: { v in update { $0.greenInRegulation = v } })
    }
    private var penaltyBinding: Binding<Int> {
        Binding(get: { entries[selectedHole]?.penalties ?? 0 },
                set: { v in update { $0.penalties = v > 0 ? v : nil } })
    }

    // MARK: - Bindings / mutations

    private var parBinding: Binding<Int> {
        Binding(
            get: { entries[selectedHole]?.par ?? 4 },
            set: { newPar in
                var e = entries[selectedHole] ?? HoleEntry(par: newPar, score: nil, putts: nil)
                e.par = newPar
                entries[selectedHole] = e
                dirtyHoles.insert(selectedHole)
            }
        )
    }

    private func setScore(_ value: Int) {
        var e = entries[selectedHole] ?? HoleEntry(par: 4, score: nil, putts: nil)
        e.score = value
        if let p = e.putts { e.putts = min(p, value) }   // putts can't exceed strokes
        entries[selectedHole] = e
        dirtyHoles.insert(selectedHole)
        advance()
    }

    /// Sets putts for the selected hole; re-tapping the current value clears it
    /// back to untracked (nil) so a mis-tap or "didn't count putts here" is
    /// recoverable per hole.
    private func setPutts(_ value: Int) {
        var e = entries[selectedHole] ?? HoleEntry(par: 4, score: nil, putts: nil)
        e.putts = (e.putts == value) ? nil : value
        entries[selectedHole] = e
        dirtyHoles.insert(selectedHole)
    }

    /// Jump to the next still-unscored, inline-editable hole after a score is
    /// entered, so a front-to-back round is pure tapping. Skips shot-owned holes
    /// (they're entered via the shot card) and stays put once everything's done.
    private func advance() {
        if let next = (1...holeCount).first(where: { !isHoleShotLocked($0) && entries[$0]?.score == nil }) {
            selectedHole = next
        }
    }

    // MARK: - Load / save

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        seedEntries()
        selectedHole = firstSelectableHole()
    }

    /// First inline-editable hole to land on: the first unscored editable hole,
    /// else any editable hole, else hole 1 (a fully shot-owned round just shows
    /// the read-only hint regardless of `selectedHole`).
    private func firstSelectableHole() -> Int {
        if let n = (1...holeCount).first(where: { !isHoleShotLocked($0) && entries[$0]?.score == nil }) { return n }
        if let n = (1...holeCount).first(where: { !isHoleShotLocked($0) }) { return n }
        return 1
    }

    /// (Re)build the in-flight grid from the round's current HoleScores. Called
    /// once on appear, and again after a shot-entry sheet dismisses so the
    /// derived score / putts show without reopening the scorecard.
    private func seedEntries() {
        var seeded: [Int: HoleEntry] = [:]
        for hole in round.holeScores {
            seeded[hole.holeNumber] = HoleEntry(
                par: hole.par, score: hole.score, putts: hole.putts,
                fairwayHit: hole.fairwayHit, greenInRegulation: hole.greenInRegulation,
                penalties: hole.penalties
            )
            if hole.putts != nil { showPutts = true }
        }
        for n in 1...holeCount where seeded[n] == nil {
            let prior = GolfScoreWriter.priorRoundPar(forHole: n, in: round)
            let inRoundPar = (1..<n).compactMap { seeded[$0]?.par }.last
            seeded[n] = HoleEntry(par: prior ?? inRoundPar ?? 4, score: nil, putts: nil)
        }
        entries = seeded
    }

    private func save() {
        guard !isSaving else { return }
        // Shot-tracked rounds derive their holes from ShotRollup; the scorecard
        // must never write them. The Save button is hidden in that mode, so this
        // is a defensive backstop only.
        guard !isShotTracked else { dismiss(); return }
        isSaving = true

        // Only write holes the user touched that carry a real score. Build the
        // inputs first so the total mirror folds them in atomically.
        var written: [GolfScoreWriter.HoleInput] = []
        for n in dirtyHoles.sorted() {
            // Never write a shot-owned hole — it's derived by ShotRollup. Such a
            // hole can't be selected/dirtied via the editor, so this is a
            // defensive backstop.
            guard !isHoleShotLocked(n) else { continue }
            guard let entry = entries[n], let score = entry.score, score >= 1 else { continue }
            // Per-hole putts: write whatever the hole carries (nil if untracked).
            // The Track Putts toggle is visibility-only — it never nulls putts on
            // save, so a putts-bearing hole survives toggling the strip off.
            let putts = entry.putts.map { min($0, score) }
            written.append(GolfScoreWriter.HoleInput(
                holeNumber: n, par: entry.par, score: score, putts: putts,
                fairwayHit: entry.par >= 4 ? entry.fairwayHit : nil,
                greenInRegulation: entry.greenInRegulation,
                penalties: entry.penalties
            ))
        }

        for input in written {
            GolfScoreWriter.upsertHole(input, in: round, context: modelContext)
        }
        GolfScoreWriter.mirrorTotalScore(in: round, justWrote: written)
        for input in written {
            GolfScoreWriter.upsertReelIfNeeded(holeNumber: input.holeNumber, par: input.par,
                                               score: input.score, in: round, context: modelContext)
        }

        do {
            try modelContext.save()
        } catch {
            isSaving = false
            ErrorHandlerService.shared.handle(error, context: "GolfScorecardView.save", showAlert: true)
            return
        }

        Haptics.success()
        dismiss()
    }
}
