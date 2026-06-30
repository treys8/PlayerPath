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

    /// The hole currently being scored. Seeded from the `holeNumber` the caller
    /// opened on, then advanced/rewound in place by the bottom nav bar so a round
    /// flows hole → hole without dismissing and re-tapping "Score Hole N".
    @State private var currentHole: Int

    enum ScoringMode: Hashable { case quick, shotByShot }

    init(game: Game, holeNumber: Int) {
        self.parent = .game(game)
        _currentHole = State(initialValue: holeNumber)
        let holes = game.holeScores ?? []
        _mode = State(initialValue: Self.initialMode(holeScores: holes,
                                                      holeNumber: holeNumber,
                                                      tracksShotByShot: game.tracksShotByShot))
        _holeHasLiveShots = State(initialValue: Self.hasLiveShots(holeScores: holes, holeNumber: holeNumber))
    }

    init(practice: Practice, holeNumber: Int) {
        self.parent = .practice(practice)
        _currentHole = State(initialValue: holeNumber)
        let holes = practice.holeScores ?? []
        _mode = State(initialValue: Self.initialMode(holeScores: holes,
                                                      holeNumber: holeNumber,
                                                      tracksShotByShot: practice.tracksShotByShot))
        _holeHasLiveShots = State(initialValue: Self.hasLiveShots(holeScores: holes, holeNumber: holeNumber))
    }

    /// Bridges the private `Parent` to the shared `GolfRoundRef` so the host can
    /// read `holeCount` / `holeScores` for navigation + per-hole mode recompute.
    private var roundRef: GolfRoundRef {
        switch parent {
        case .game(let g):     return .game(g)
        case .practice(let p): return .practice(p)
        }
    }

    private var holeCount: Int { roundRef.holeCount }

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
                    // Persist ONLY on a real user tap of the switch — navigation
                    // recomputes `mode` per hole (below) and must not write the
                    // round's shot-by-shot default. A plain `.onChange(of: mode)`
                    // can't tell the two apart, so route persistence through the
                    // binding setter instead.
                    Picker("Scoring mode", selection: Binding(
                        get: { mode },
                        set: { newMode in
                            mode = newMode
                            persistModeChange(newMode)
                        }
                    )) {
                        Text("Quick").tag(ScoringMode.quick)
                        Text("Shot-by-shot").tag(ScoringMode.shotByShot)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, .spacingLarge)
                    .padding(.top, .spacingSmall)
                    .padding(.bottom, .spacingSmall)
                } else {
                    // Shot-owned hole: the Quick switch is hidden (two-writer
                    // guard). Show a static badge so the locked mode is explicit.
                    HStack(spacing: 6) {
                        Image(systemName: "scope")
                        Text("Shot by shot")
                    }
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, .spacingSmall)
                    .padding(.bottom, .spacingSmall)
                }

                content
                    .id(currentHole)   // fresh child per hole → re-seeds par/score/shots
            }
            .navigationTitle("Hole \(currentHole)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .presentationDetents([.medium, .large], selection: $detent)
            .presentationDragIndicator(.visible)
        }
        // Recompute the per-hole mode/lock when navigating. This deliberately does
        // NOT persist anything (see the Picker binding) — stepping between holes
        // must never flip the round's remembered shot-by-shot default.
        .onChange(of: currentHole) { _, hole in
            let holes = roundRef.holeScores
            holeHasLiveShots = Self.hasLiveShots(holeScores: holes, holeNumber: hole)
            mode = Self.initialMode(holeScores: holes, holeNumber: hole,
                                    tracksShotByShot: roundRef.tracksShotByShot)
        }
    }

    /// Save-and-go-back / advance for the bottom nav bar (strict sequential).
    /// On the last hole the primary action dismisses instead of advancing.
    private func goPrev()  { if currentHole > 1 { withAnimation(.none) { currentHole -= 1 } } }
    private func advance() {
        if currentHole < holeCount { withAnimation(.none) { currentHole += 1 } } else { dismiss() }
    }

    @ViewBuilder private var content: some View {
        // A shot-owned hole ALWAYS renders shot-by-shot, regardless of `mode` —
        // the quick editor must never render over a hole with live shots (the
        // two-writer guard), even if the mode state were somehow stale.
        if holeIsShotLocked || mode == .shotByShot {
            switch parent {
            case .game(let g):
                ShotByShotContent(game: g, holeNumber: currentHole, holeCount: holeCount,
                                  onPrev: goPrev, onAdvance: advance,
                                  onLiveShotsChanged: { holeHasLiveShots = $0 },
                                  onRevertToQuick: { mode = .quick; persistModeChange(.quick) })
            case .practice(let p):
                ShotByShotContent(practice: p, holeNumber: currentHole, holeCount: holeCount,
                                  onPrev: goPrev, onAdvance: advance,
                                  onLiveShotsChanged: { holeHasLiveShots = $0 },
                                  onRevertToQuick: { mode = .quick; persistModeChange(.quick) })
            }
        } else {
            switch parent {
            case .game(let g):
                QuickScoreContent(game: g, holeNumber: currentHole, holeCount: holeCount,
                                  onPrev: goPrev, onAdvance: advance)
            case .practice(let p):
                QuickScoreContent(practice: p, holeNumber: currentHole, holeCount: holeCount,
                                  onPrev: goPrev, onAdvance: advance)
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
