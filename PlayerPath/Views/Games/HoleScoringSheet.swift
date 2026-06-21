//
//  HoleScoringSheet.swift
//  PlayerPath
//
//  Unified per-hole golf scoring sheet. Tapping "Score Hole N" anywhere opens
//  this; a Quick | Shot-by-shot segmented switch picks the entry style per hole.
//  It owns the NavigationStack, title, Cancel button and detents, and hosts one
//  of two content bodies — `QuickScoreContent` (hole-at-a-time) or
//  `ShotByShotContent` (the shot-by-shot timeline). Each content view contributes
//  its own confirmation toolbar item (Save / Done).
//
//  The per-round `tracksShotByShot` flag is reused as a remembered default: the
//  in-sheet switch sets it (so the rest of the round defaults the same way) plus
//  a global `GolfPrefs.preferredShotByShot` (so future rounds inherit it). A hole
//  that already has live shots is owned by ShotRollup — it opens locked to
//  shot-by-shot with no switch, preserving the two-writer guard.
//

import SwiftUI
import SwiftData

struct HoleScoringSheet: View {
    private enum Parent {
        case game(Game)
        case practice(Practice)
    }
    private let parent: Parent
    let holeNumber: Int

    enum ScoringMode: Hashable { case quick, shotByShot }

    init(game: Game, holeNumber: Int) {
        self.parent = .game(game)
        self.holeNumber = holeNumber
        let holes = game.holeScores ?? []
        _mode = State(initialValue: Self.initialMode(holeScores: holes,
                                                      holeNumber: holeNumber,
                                                      tracksShotByShot: game.tracksShotByShot))
        _holeHasLiveShots = State(initialValue: Self.hasLiveShots(holeScores: holes, holeNumber: holeNumber))
    }

    init(practice: Practice, holeNumber: Int) {
        self.parent = .practice(practice)
        self.holeNumber = holeNumber
        let holes = practice.holeScores ?? []
        _mode = State(initialValue: Self.initialMode(holeScores: holes,
                                                      holeNumber: holeNumber,
                                                      tracksShotByShot: practice.tracksShotByShot))
        _holeHasLiveShots = State(initialValue: Self.hasLiveShots(holeScores: holes, holeNumber: holeNumber))
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(GolfPrefs.preferredShotByShot) private var preferredShotByShot = false

    @State private var mode: ScoringMode
    @State private var detent: PresentationDetent = .large

    /// Whether the hole currently has live (non-soft-deleted) shots. Seeded in
    /// `init`, then kept current by `ShotByShotContent` via `onLiveShotsChanged`
    /// — a relationship-array read in `body` is NOT a reliable SwiftUI dependency
    /// for a shot inserted into an EXISTING HoleScore, so we report it explicitly.
    @State private var holeHasLiveShots: Bool

    /// A hole that carries live shots is owned by ShotRollup — it must stay
    /// shot-by-shot (no Quick switch), so the quick editor can never two-write a
    /// shot-derived hole.
    private var holeIsShotLocked: Bool { holeHasLiveShots }

    private static func hasLiveShots(holeScores: [HoleScore], holeNumber: Int) -> Bool {
        (holeScores.first { $0.holeNumber == holeNumber }?.shots ?? [])
            .contains { !$0.isDeletedRemotely }
    }

    /// Initial mode: locked to shot-by-shot if the hole has shots; Quick if it
    /// has a saved hole-at-a-time score and no shots (editing what's there);
    /// otherwise the round's remembered default.
    private static func initialMode(holeScores: [HoleScore], holeNumber: Int, tracksShotByShot: Bool) -> ScoringMode {
        if hasLiveShots(holeScores: holeScores, holeNumber: holeNumber) { return .shotByShot }
        let hole = holeScores.first { $0.holeNumber == holeNumber }
        if let hole, hole.score > 0 { return .quick }
        return tracksShotByShot ? .shotByShot : .quick
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !holeIsShotLocked {
                    Picker("Scoring mode", selection: $mode) {
                        Text("Quick").tag(ScoringMode.quick)
                        Text("Shot-by-shot").tag(ScoringMode.shotByShot)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, .spacingLarge)
                    .padding(.top, .spacingSmall)
                    .padding(.bottom, .spacingSmall)
                }

                content
            }
            .navigationTitle("Hole \(holeNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .presentationDetents([.medium, .large], selection: $detent)
            .presentationDragIndicator(.visible)
        }
        .onChange(of: mode) { _, newMode in persistModeChange(newMode) }
    }

    @ViewBuilder private var content: some View {
        // A shot-owned hole ALWAYS renders shot-by-shot, regardless of `mode` —
        // the quick editor must never render over a hole with live shots (the
        // two-writer guard), even if the mode state were somehow stale.
        if holeIsShotLocked || mode == .shotByShot {
            switch parent {
            case .game(let g):
                ShotByShotContent(game: g, holeNumber: holeNumber,
                                  onLiveShotsChanged: { holeHasLiveShots = $0 })
            case .practice(let p):
                ShotByShotContent(practice: p, holeNumber: holeNumber,
                                  onLiveShotsChanged: { holeHasLiveShots = $0 })
            }
        } else {
            switch parent {
            case .game(let g):     QuickScoreContent(game: g, holeNumber: holeNumber)
            case .practice(let p): QuickScoreContent(practice: p, holeNumber: holeNumber)
            }
        }
    }

    /// Remember the chosen mode for the rest of the round (`tracksShotByShot`)
    /// and for future rounds (`preferredShotByShot`). Setting `needsSync` is how
    /// the changed default reaches other devices — mirrors the old mid-round
    /// toggle. Locked holes never write (they have no switch).
    private func persistModeChange(_ newMode: ScoringMode) {
        guard !holeIsShotLocked else { return }
        let shotByShot = (newMode == .shotByShot)
        preferredShotByShot = shotByShot
        switch parent {
        case .game(let g):
            g.tracksShotByShot = shotByShot
            g.needsSync = true
        case .practice(let p):
            p.tracksShotByShot = shotByShot
            p.needsSync = true
        }
        ErrorHandlerService.shared.saveContext(modelContext, caller: "HoleScoringSheet.modeChange")
        Haptics.light()
    }
}
