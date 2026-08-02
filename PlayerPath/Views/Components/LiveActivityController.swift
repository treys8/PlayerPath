//
//  LiveActivityController.swift
//  PlayerPath
//
//  Shared behavior behind the "Live Now" cards. Every live surface — the Journal
//  (the athlete Home tab) and the retired DashboardView — drives the same four
//  actions on a live activity: score the current hole, end it, record into it,
//  and show a spinner while the end is in flight. This owns that state and logic
//  once, so a card wired on one surface behaves identically on the other.
//
//  Views hold one as `@State` and bind the sheet/cover items off it. The
//  ModelContext is passed per call rather than stored, so the controller can be
//  constructed by `@State` (which runs before `@Environment` is available) and
//  never outlives a context.
//

import SwiftUI
import SwiftData

/// Sheet target for `HoleScoringSheet`, opened by a live card's "Score Hole X"
/// CTA. Carries the resolved hole so the sheet opens on the hole the card
/// labelled — the two can't drift.
struct LiveScoreTarget: Identifiable {
    enum Parent {
        case game(Game)
        case practice(Practice)
    }
    let id = UUID()
    let parent: Parent
    let holeNumber: Int
}

@MainActor
@Observable
final class LiveActivityController {

    /// Activities whose End pill is mid-flight — drives the card's spinner and
    /// makes End single-flight, so a double-tap can't run `end()` twice.
    private(set) var endingGameIDs: Set<UUID> = []
    private(set) var endingPracticeIDs: Set<UUID> = []

    /// Guards the async capture-permission check so a double-tap on Record can't
    /// open two camera covers. Readable so callers can `.disabled()` their button
    /// while it runs.
    private(set) var isCheckingPermissions = false

    /// Hole-scoring sheet target. Nil = closed.
    var scoreTarget: LiveScoreTarget?
    /// Recorder cover targets — the clip attaches to whichever is set (clip→parent
    /// wiring lives in the recorder / ClipPersistenceService).
    var recordingGame: Game?
    var recordingPractice: Practice?

    func isEnding(_ game: Game) -> Bool { endingGameIDs.contains(game.id) }
    func isEnding(_ practice: Practice) -> Bool { endingPracticeIDs.contains(practice.id) }

    // MARK: - End

    /// End a live game from its card. Delegates to `GameService` so end-of-game
    /// side effects (stats recalc, milestone/banner/clip-nudge, sync) stay in one
    /// place rather than being re-implemented per surface.
    func endGame(_ game: Game, in modelContext: ModelContext) {
        guard !endingGameIDs.contains(game.id) else { return }
        endingGameIDs.insert(game.id)
        Haptics.light()

        let gameID = game.id
        Task { @MainActor in
            defer { endingGameIDs.remove(gameID) }
            await GameService(modelContext: modelContext).end(game)
        }
    }

    /// End a live practice (round or range session) from its card.
    func endPractice(_ practice: Practice, in modelContext: ModelContext) {
        guard !endingPracticeIDs.contains(practice.id) else { return }
        endingPracticeIDs.insert(practice.id)
        Haptics.light()

        let practiceID = practice.id
        Task { @MainActor in
            defer { endingPracticeIDs.remove(practiceID) }
            await PracticeService(modelContext: modelContext).end(practice)
        }
    }

    // MARK: - Score

    /// Open `HoleScoringSheet` on the hole that still needs a score, without
    /// navigating into the detail screen. No-ops once the round is fully scored —
    /// the card's CTA is hidden in that state, so this guard is belt-and-braces.
    ///
    /// Must be `nextUnscoredHole`, NOT `currentHole`: the card labels its button
    /// with the first unscored hole, so opening the sheet on the attribution hole
    /// (highest scored + 1) would land on a different hole than the button named.
    func presentScoreHole(for game: Game) {
        guard let hole = LiveHoleTracker.shared.nextUnscoredHole(for: game) else { return }
        scoreTarget = LiveScoreTarget(parent: .game(game), holeNumber: hole)
    }

    func presentScoreHole(for practice: Practice) {
        guard let hole = LiveHoleTracker.shared.nextUnscoredHole(for: practice) else { return }
        scoreTarget = LiveScoreTarget(parent: .practice(practice), holeNumber: hole)
    }

    // MARK: - Record

    /// Open the recorder over the current screen, bound to the live game so the
    /// captured clip attaches to it.
    func recordInto(game: Game, context: String) {
        Task { @MainActor in
            guard await ensureCapturePermission(context: context) else { return }
            recordingGame = game
        }
    }

    /// Recorder bound to a live practice, so swings attribute to that session.
    func recordInto(practice: Practice, context: String) {
        Task { @MainActor in
            guard await ensureCapturePermission(context: context) else { return }
            recordingPractice = practice
        }
    }

    /// The capture-permission gate every Record path goes through: single-flight,
    /// and it never presents a camera we aren't authorized to fill (a black
    /// preview). Returns true when the caller should present — surfaces that own
    /// their own camera cover (DashboardView's Quick Actions) call this directly.
    func ensureCapturePermission(context: String) async -> Bool {
        guard !isCheckingPermissions else { return false }
        isCheckingPermissions = true
        defer { isCheckingPermissions = false }

        let status = await RecorderPermissions.ensureCapturePermissions(context: context)
        guard status == .granted else { return false }
        Haptics.medium()
        return true
    }
}
