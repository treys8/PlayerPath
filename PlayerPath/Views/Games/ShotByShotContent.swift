//
//  ShotByShotContent.swift
//  PlayerPath
//
//  Shot-by-shot entry body for one golf hole (SchemaV30) — the "Direction B"
//  whole-hole timeline. Each logged shot is a tap-to-edit `ShotLogRow`; the
//  active card at the bottom enters (or edits) one shot: pick club → tap result,
//  with the lie auto-chained from the previous result. Reach the green → the
//  active card becomes the putts stepper; tap Holed → the hole completes.
//
//  Hosted inside `HoleScoringSheet` (which owns the NavigationStack, title,
//  Cancel button and detents); this view contributes the timeline + a Done
//  toolbar item. The hole's score / FIR / GIR / putts are DERIVED from the shots
//  (ShotRollup) and written through the SAME GolfScoreWriter sequence as
//  QuickScoreContent, so the scorecard, totals and birdie reels keep working and
//  nothing is entered twice. Serves both a Game and a golf Practice round.
//

import SwiftUI
import SwiftData

struct ShotByShotContent: View {
    private enum Parent {
        case game(Game)
        case practice(Practice)
    }
    private let parent: Parent
    let holeNumber: Int

    /// Reports `!shots.isEmpty` to the host (`HoleScoringSheet`) whenever the
    /// live-shot count crosses 0, so the host can lock/unlock the Quick switch
    /// reliably (a shot inserted into an existing HoleScore isn't a dependable
    /// SwiftUI dependency for the host's relationship read).
    private let onLiveShotsChanged: ((Bool) -> Void)?
    /// Called after the user clears this hole's shots to switch the host sheet
    /// back to Quick entry (the host owns the mode state).
    private let onRevertToQuick: (() -> Void)?

    init(game: Game, holeNumber: Int,
         onLiveShotsChanged: ((Bool) -> Void)? = nil,
         onRevertToQuick: (() -> Void)? = nil) {
        self.parent = .game(game)
        self.holeNumber = holeNumber
        self.onLiveShotsChanged = onLiveShotsChanged
        self.onRevertToQuick = onRevertToQuick
    }

    init(practice: Practice, holeNumber: Int,
         onLiveShotsChanged: ((Bool) -> Void)? = nil,
         onRevertToQuick: (() -> Void)? = nil) {
        self.parent = .practice(practice)
        self.holeNumber = holeNumber
        self.onLiveShotsChanged = onLiveShotsChanged
        self.onRevertToQuick = onRevertToQuick
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Most-recently-used clubs (CSV of raw values) for the quick-access row.
    @AppStorage(GolfPrefs.recentlyUsedClubs) private var recentClubsRaw = ""

    @State private var par: Int = 4
    @State private var putts: Int = 0
    /// Lie for the shot about to be logged (auto-chained, correctable).
    @State private var currentLie: ShotLie = .tee
    @State private var selectedClub: Club? = nil
    @State private var pendingDistance: Int? = nil
    @State private var pendingPenalty: Int = 0
    @State private var editingShot: Shot? = nil

    @State private var shots: [Shot] = []
    @State private var holeScore: HoleScore?
    @State private var didLoad = false
    @State private var showRevertConfirm = false
    /// True when this hole already had a real hole-at-a-time score (no shots)
    /// when opened — e.g. shot mode flipped on mid-round over a scored hole.
    /// Guards against a partial shot-derived score clobbering it until the hole
    /// is fully re-logged.
    @State private var hadPriorScore = false

    // MARK: - Round bridging

    private var roundRef: GolfRoundRef {
        switch parent {
        case .game(let g):     return .game(g)
        case .practice(let p): return .practice(p)
        }
    }

    private var parentHoles: [HoleScore] { roundRef.holeScores }

    // MARK: - Derived hole state

    private var holedOut: Bool { shots.last?.outcome == .holed }
    private var ballOnGreen: Bool {
        guard let last = shots.last else { return false }
        return last.outcome.reachedGreen && last.outcome != .holed
    }

    /// Putts only count once the ball is on the green; a holed chip finishes
    /// with zero putts; mid-hole (not yet on the green) putts are nil.
    private var puttsValue: Int? {
        if holedOut { return 0 }
        guard ballOnGreen else { return nil }
        return putts
    }

    private var derivedInput: GolfScoreWriter.HoleInput {
        ShotRollup.deriveInput(holeNumber: holeNumber, par: par, shots: shots, putts: puttsValue)
    }

    private var isComplete: Bool { ShotRollup.isComplete(shots: shots, putts: puttsValue) }

    private var currentContext: ShotContext? {
        ShotContext.forLie(currentLie, par: par)
    }

    private var recommendedClubs: Set<Club> {
        ShotClubRecommender.recommended(lie: currentLie, par: par, distanceBefore: pendingDistance)
    }

    /// Inline yardage entry — writes `pendingDistance`, dropping non-positive.
    private var distanceFieldBinding: Binding<String> {
        Binding(
            get: { pendingDistance.map(String.init) ?? "" },
            set: { pendingDistance = Int($0).flatMap { $0 > 0 ? $0 : nil } }
        )
    }

    /// Stepper view of the same yardage (0 == unset), for ±5-yard nudges without
    /// the keyboard.
    private var distanceStepperBinding: Binding<Int> {
        Binding(
            get: { pendingDistance ?? 0 },
            set: { pendingDistance = $0 > 0 ? $0 : nil }
        )
    }

    /// Distance of the most recent shot that recorded one — backs a "same as last"
    /// shortcut (often you're hitting from a known sprinkler-head yardage again).
    private var lastApproachDistance: Int? {
        shots.reversed().compactMap { $0.distanceBefore }.first
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: .spacingLarge) {
                slimHeader

                if !shots.isEmpty {
                    VStack(spacing: .spacingSmall) {
                        ForEach(shots) { shot in
                            ShotLogRow(shot: shot, isEditing: editingShot?.id == shot.id) {
                                beginEdit(shot)
                            }
                        }
                        if let p = puttsValue, p > 0 {
                            puttsSummaryRow(p)
                        }
                    }
                }

                if editingShot != nil {
                    shootingCard
                } else if holedOut {
                    completionCard
                } else if ballOnGreen {
                    puttingCard
                } else {
                    shootingCard
                }
            }
            .padding(.spacingLarge)
        }
        .ppDetailBackground()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog("Clear all shots on this hole?",
                            isPresented: $showRevertConfirm, titleVisibility: .visible) {
            Button("Clear & Use Quick", role: .destructive) { revertToQuick() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes the shots logged for hole \(holeNumber) and switches to quick score entry. Your other holes aren't affected.")
        }
        .onAppear { loadIfNeeded() }
    }

    // MARK: - Slim header (Par chip + running score)

    private var slimHeader: some View {
        HStack(spacing: .spacingMedium) {
            Menu {
                Picker("Par", selection: $par) {
                    ForEach(3...6, id: \.self) { Text("Par \($0)").tag($0) }
                }
            } label: {
                Text("Par \(par)")
                    .font(.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.golfAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.golfAccent.opacity(0.12)))
            }
            .onChange(of: par) { _, _ in persistIfDirty() }

            Spacer()

            if !shots.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(derivedInput.score)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.parRelative(derivedInput.score - par))
                    Text(throughLabel)
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var throughLabel: String {
        let n = shots.count
        return "thru \(n) shot\(n == 1 ? "" : "s")"
    }

    private func puttsSummaryRow(_ count: Int) -> some View {
        HStack(spacing: .spacingMedium) {
            Image(systemName: "circle.dotted")
                .font(.bodyMedium)
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
            Text("\(count) putt\(count == 1 ? "" : "s")")
                .font(.bodyMedium)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, .spacingMedium)
    }

    // MARK: - Shooting / editing card

    private var shootingCard: some View {
        VStack(alignment: .leading, spacing: .spacingMedium) {
            if let editing = editingShot {
                HStack {
                    Text("Editing shot \(editing.shotNumber)")
                        .font(.labelMedium)
                        .foregroundColor(Theme.golfAccent)
                    Spacer()
                    Button("Cancel edit") { cancelEdit() }
                        .font(.bodySmall)
                }
            }

            // Lie chip — auto-chained, tap to correct.
            Menu {
                Picker("Lie", selection: $currentLie) {
                    ForEach(ShotLie.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } label: {
                Label("from \(currentLie.displayName)", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .font(.bodyMedium)
                    .foregroundColor(Theme.golfAccent)
            }

            Text("CLUB")
                .font(.labelMedium)
                .foregroundColor(.secondary)
            ShotClubGrid(selected: selectedClub, recommended: recommendedClubs) { club in
                selectedClub = (selectedClub == club) ? nil : club
            }

            // Distance (approach shots only) on its own row so the field, a ±5
            // stepper, and the "same as last" shortcut all fit comfortably.
            if currentContext == .approach {
                HStack(spacing: .spacingSmall) {
                    HStack(spacing: 6) {
                        Image(systemName: "ruler")
                            .font(.bodySmall)
                            .foregroundColor(Theme.golfAccent)
                        TextField("yds", text: distanceFieldBinding)
                            .keyboardType(.numberPad)
                            .font(.bodyMedium)
                            .monospacedDigit()
                            .frame(width: 44)
                            .multilineTextAlignment(.center)
                        Text("yds")
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                        Stepper("Distance", value: distanceStepperBinding, in: 0...400, step: 5)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.golfAccent.opacity(0.10)))

                    if let last = lastApproachDistance, last != pendingDistance {
                        Button {
                            Haptics.selection()
                            pendingDistance = last
                        } label: {
                            Label("\(last)", systemImage: "arrow.uturn.left")
                                .font(.bodySmall)
                        }
                    }
                    Spacer()
                }
            }

            // Penalty + Undo row.
            HStack(spacing: .spacingSmall) {
                Menu {
                    Picker("Penalty", selection: $pendingPenalty) {
                        Text("No penalty").tag(0)
                        Text("Penalty +1").tag(1)
                        Text("Penalty +2").tag(2)
                    }
                } label: {
                    Label(pendingPenalty == 0 ? "Penalty" : "+\(pendingPenalty)",
                          systemImage: "exclamationmark.triangle")
                        .font(.bodySmall)
                        .foregroundColor(pendingPenalty == 0 ? .secondary : Theme.warning)
                }

                Spacer()

                if editingShot == nil, !shots.isEmpty {
                    Button(role: .destructive) { deleteLast() } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.bodySmall)
                    }
                }
            }

            if let context = currentContext {
                Text("RESULT")
                    .font(.labelMedium)
                    .foregroundColor(.secondary)
                ShotResultButtons(context: context) { outcome in
                    commit(outcome)
                }
            }

            if editingShot != nil {
                Button(role: .destructive) {
                    if let editing = editingShot { delete(editing) }
                } label: {
                    Label("Delete shot", systemImage: "trash")
                        .font(.bodyMedium)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, .spacingSmall)
            } else if !shots.isEmpty {
                // Escape hatch off a shot-tracked hole without deleting each shot
                // one at a time (the mode switch is otherwise locked while shots
                // exist — the two-writer guard).
                Button(role: .destructive) {
                    showRevertConfirm = true
                } label: {
                    Label("Clear shots & use Quick", systemImage: "arrow.uturn.backward.circle")
                        .font(.bodySmall)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, .spacingSmall)
            }
        }
        .padding(.spacingMedium)
        .background(
            RoundedRectangle(cornerRadius: .cornerLarge)
                .fill(Color(.secondarySystemBackground).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: .cornerLarge)
                .stroke(Theme.golfAccent.opacity(editingShot != nil ? 0.9 : 0.4), lineWidth: 1.5)
        )
    }

    // MARK: - Putting

    private var puttingCard: some View {
        VStack(spacing: .spacingMedium) {
            Text("ON THE GREEN")
                .font(.labelMedium)
                .foregroundColor(.secondary)
            Text("How many putts?")
                .font(.bodyLarge)
            // One-tap chip grid (consistent with quick scoring) instead of ±1
            // buttons — a 4-putt is one tap, not three.
            NumberChipGrid(range: 1...6, selected: putts, par: nil) { value in
                putts = value
                persistIfDirty()
            }
            doneButton(title: "Hole out · Done")
                .disabled(putts < 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.spacingLarge)
        .background(
            RoundedRectangle(cornerRadius: .cornerLarge)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Completion

    private var completionCard: some View {
        VStack(spacing: .spacingSmall) {
            Text(HoleScore.diffLabel(score: derivedInput.score, par: par).uppercased())
                .font(.headingSmall)
                .foregroundColor(.parRelative(derivedInput.score - par))
            Text("\(derivedInput.score)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.parRelative(derivedInput.score - par))
            doneButton(title: "Done")
        }
        .frame(maxWidth: .infinity)
        .padding(.spacingLarge)
        .background(
            RoundedRectangle(cornerRadius: .cornerLarge)
                .fill(Theme.golfAccent.opacity(0.10))
        )
    }

    private func doneButton(title: String) -> some View {
        Button {
            Haptics.success()
            dismiss()
        } label: {
            Text(title)
                .font(.bodyLarge)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: .cornerLarge).fill(Theme.golfAccent)
                )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Load

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        if let existing = parentHoles.first(where: { $0.holeNumber == holeNumber }) {
            holeScore = existing
            par = existing.par
            putts = existing.putts ?? 0
            let liveShots = (existing.shots ?? []).filter { !$0.isDeletedRemotely }
            shots = liveShots.sorted { $0.shotNumber < $1.shotNumber }
            hadPriorScore = existing.score > 0 && liveShots.isEmpty
        } else {
            // Seed par the same way QuickScoreContent does: prior round at this
            // course → most recent prior hole this round → 4.
            let priorHoles = parentHoles.filter { $0.holeNumber < holeNumber }
            let inRoundPar = priorHoles.max(by: { $0.holeNumber < $1.holeNumber })?.par
            par = GolfScoreWriter.priorRoundPar(forHole: holeNumber, in: roundRef) ?? inRoundPar ?? 4
        }
        currentLie = shots.last.map { ShotLieChain.nextLie(after: $0.outcome) } ?? .tee
        onLiveShotsChanged?(!shots.isEmpty)
    }

    // MARK: - Mutations

    private func ensureHoleScore() -> HoleScore {
        if let h = holeScore { return h }
        if let existing = parentHoles.first(where: { $0.holeNumber == holeNumber }) {
            holeScore = existing
            return existing
        }
        let h = HoleScore(holeNumber: holeNumber, par: par, score: 0)
        switch parent {
        case .game(let g):     h.game = g
        case .practice(let p): h.practice = p
        }
        modelContext.insert(h)
        holeScore = h
        return h
    }

    private func commit(_ outcome: ShotOutcome) {
        if let editing = editingShot {
            editing.club = selectedClub
            editing.lie = currentLie
            editing.outcome = outcome
            editing.distanceBefore = pendingDistance
            editing.penaltyStrokes = pendingPenalty
            editing.updatedAt = Date()
            editing.version += 1   // bump so the edit beats stale copies on other devices
            editing.needsSync = true
            editingShot = nil
            shots = shots.sorted { $0.shotNumber < $1.shotNumber }   // force refresh
        } else {
            let hole = ensureHoleScore()
            let shot = Shot(
                shotNumber: shots.count + 1,
                club: selectedClub,
                lie: currentLie,
                outcome: outcome,
                penaltyStrokes: pendingPenalty,
                distanceBefore: pendingDistance
            )
            shot.holeScore = hole
            modelContext.insert(shot)
            shots.append(shot)
        }

        // Remember the club for the quick-access "Recent" row before resetting.
        if let club = selectedClub { recordRecentClub(club) }

        // Reset the draft and auto-chain the next lie from the actual last shot.
        selectedClub = nil
        pendingDistance = nil
        pendingPenalty = 0
        currentLie = shots.last.map { ShotLieChain.nextLie(after: $0.outcome) } ?? .tee

        // Seed a sensible default putt count the moment the ball reaches the green.
        if ballOnGreen && putts == 0 { putts = 2 }

        onLiveShotsChanged?(!shots.isEmpty)
        persist()
    }

    private func beginEdit(_ shot: Shot) {
        editingShot = shot
        selectedClub = shot.club
        currentLie = shot.lie
        pendingDistance = shot.distanceBefore
        pendingPenalty = shot.penaltyStrokes
    }

    private func cancelEdit() {
        editingShot = nil
        selectedClub = nil
        pendingDistance = nil
        pendingPenalty = 0
        currentLie = shots.last.map { ShotLieChain.nextLie(after: $0.outcome) } ?? .tee
    }

    /// Fast "oops" — drops the most recent shot.
    private func deleteLast() {
        guard let last = shots.max(by: { $0.shotNumber < $1.shotNumber }) else { return }
        delete(last)
    }

    /// Delete ANY shot, then renumber the survivors. Soft-deletes a synced shot
    /// (so `syncShots` tombstones the remote doc — a local hard-delete would
    /// resurrect it on the next reconcile and re-inflate the score); hard-deletes
    /// a never-synced one.
    private func delete(_ shot: Shot) {
        if editingShot?.id == shot.id { editingShot = nil }
        shots.removeAll { $0.id == shot.id }

        if shot.firestoreId == nil {
            shot.holeScore = nil
            modelContext.delete(shot)
        } else {
            shot.isDeletedRemotely = true
            shot.version += 1
            shot.needsSync = true
            shot.updatedAt = Date()
        }

        renumberShots()

        // Reset the draft + re-chain the next lie from the new last shot.
        selectedClub = nil
        pendingDistance = nil
        pendingPenalty = 0
        currentLie = shots.last.map { ShotLieChain.nextLie(after: $0.outcome) } ?? .tee

        if shots.isEmpty { clearEmptyHole() }
        onLiveShotsChanged?(!shots.isEmpty)
        persist()
    }

    /// Discard EVERY shot on this hole and hand control back to Quick entry —
    /// the one-tap way off a shot-tracked hole (the mode switch is locked while
    /// shots exist). Mirrors `delete()`'s per-shot soft/hard-delete rule so synced
    /// shots tombstone rather than resurrect, reverts the hole via
    /// `clearEmptyHole` (which respects a prior quick score), then unlocks the
    /// host and switches it to Quick.
    private func revertToQuick() {
        for shot in shots {
            if shot.firestoreId == nil {
                shot.holeScore = nil
                modelContext.delete(shot)
            } else {
                shot.isDeletedRemotely = true
                shot.version += 1
                shot.needsSync = true
                shot.updatedAt = Date()
            }
        }
        shots.removeAll()

        editingShot = nil
        selectedClub = nil
        pendingDistance = nil
        pendingPenalty = 0
        currentLie = .tee

        clearEmptyHole()
        onLiveShotsChanged?(false)
        persist()
        onRevertToQuick?()
    }

    /// All shots gone. A FRESH shot-tracked hole's `HoleScore` exists only to
    /// back the shots, so revert the hole to unscored — leaving a stale derived
    /// score would inflate the round total, demote nothing, and (score 0) render
    /// as a phantom "Albatross". A hole that had a PRIOR quick score is left
    /// untouched: `persist()` never overwrote it (`hadPriorScore` guard), so
    /// deleting the shots correctly reverts to that quick score.
    private func clearEmptyHole() {
        guard !hadPriorScore, let hole = holeScore else { return }
        if hole.firestoreId == nil {
            // Never synced — hard-delete; no remote to resurrect from.
            modelContext.delete(hole)
        } else {
            // Synced — tombstone (score 0 so the total re-sums correctly without
            // it); syncHoleScores pushes isDeleted and the next reconcile drops
            // the local row.
            hole.score = 0
            hole.putts = nil
            hole.fairwayHit = nil
            hole.greenInRegulation = nil
            hole.penalties = nil
            hole.isDeletedRemotely = true
            hole.version += 1
            hole.needsSync = true
            hole.updatedAt = Date()
        }
        holeScore = nil
        // Re-mirror the round total without this hole and demote any birdie reel.
        // Force this hole's contribution to 0 via `justWrote` so the sum is
        // correct even if SwiftData still lists the just-deleted row pre-save.
        GolfScoreWriter.mirrorTotalScore(
            in: roundRef,
            justWrote: [GolfScoreWriter.HoleInput(holeNumber: holeNumber, par: par, score: 0, putts: nil)]
        )
        GolfScoreWriter.upsertReelIfNeeded(holeNumber: holeNumber, par: par, score: 0,
                                           in: roundRef, context: modelContext)
    }

    /// Compact the remaining live shots to 1…n. `shotNumber` is a synced sort
    /// field (doc id is the UUID), so any change must bump version + needsSync or
    /// the reorder is local-only and re-inflates on the next reconcile.
    private func renumberShots() {
        let ordered = shots.sorted { $0.shotNumber < $1.shotNumber }
        for (idx, shot) in ordered.enumerated() {
            let newNumber = idx + 1
            if shot.shotNumber != newNumber {
                shot.shotNumber = newNumber
                shot.version += 1
                shot.needsSync = true
                shot.updatedAt = Date()
            }
        }
        shots = ordered
    }

    /// Push a just-used club to the front of the recents list (deduped, capped at
    /// 5). Club raw values contain no commas, so a plain CSV is safe.
    private func recordRecentClub(_ club: Club) {
        var recent = recentClubsRaw.split(separator: ",").map(String.init)
        recent.removeAll { $0 == club.rawValue }
        recent.insert(club.rawValue, at: 0)
        recentClubsRaw = recent.prefix(5).joined(separator: ",")
    }

    // MARK: - Persist (the shared GolfScoreWriter sequence)

    private func persistIfDirty() {
        guard !shots.isEmpty else { return }
        persist()
    }

    private func persist() {
        // Derive into the HoleScore when there are shots — but never overwrite a
        // pre-existing hole-at-a-time score with a PARTIAL shot-derived one: for
        // such a hole, hold off until it's fully re-logged (isComplete). A fresh
        // shot-tracked hole writes live (running score). The birdie reel only
        // fires once the hole is complete (idempotent; avoids a provisional reel).
        if !shots.isEmpty && (!hadPriorScore || isComplete) {
            let input = derivedInput
            GolfScoreWriter.upsertHole(input, in: roundRef, context: modelContext)
            GolfScoreWriter.mirrorTotalScore(in: roundRef, justWrote: [input])
            if isComplete {
                GolfScoreWriter.upsertReelIfNeeded(holeNumber: holeNumber, par: par,
                                                   score: input.score, in: roundRef, context: modelContext)
            }
        }
        // Always persist the shots themselves (incl. soft-deletes) + any insert.
        ErrorHandlerService.shared.saveContext(modelContext, caller: "ShotByShotContent.persist")
    }
}
