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

/// The one wording for "end a live activity?", used by every End confirmation
/// (Live Now accessory, Journal cards, Games swipe, detail screens) so they can
/// never disagree about what ending does.
enum LiveEndPrompt {
    static func title(isGolf: Bool) -> String { isGolf ? "End Round?" : "End Game?" }
    static func button(isGolf: Bool) -> String { isGolf ? "End Round" : "End Game" }
    /// True on both counts: ending finalizes stats, and Restart (detail `•••`
    /// menu, shown once `isComplete`) undoes it.
    static func message(isGolf: Bool) -> String {
        "This finalizes its \(isGolf ? "score" : "stats"). Ended by mistake? Restart it from the \(isGolf ? "round" : "game")'s ••• menu."
    }

    static func practiceTitle(isRangeSession: Bool) -> String { isRangeSession ? "End Session?" : "End Round?" }
    static func practiceButton(isRangeSession: Bool) -> String { isRangeSession ? "End Session" : "End Round" }
    /// Unlike games, practices stay fully editable after ending — ending only
    /// stops the live strip and live-hole clip attribution.
    static let practiceMessage = "This ends the live session. You can still add videos, photos, and notes afterward."
}

/// An End confirmation awaiting the user's answer. The strings are resolved
/// when End is tapped, NOT while the dialog renders: a sync or athlete delete
/// can remove the model while the dialog is up, and reading `season` off a
/// deleted @Model to build a title traps. The action side re-guards instead.
struct PendingLiveEnd {
    enum Target {
        case game(Game)
        case practice(Practice)
    }
    let target: Target
    let title: String
    let button: String
    let message: String
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

    /// End confirmation shown by MainTabView's single dialog. Nil = closed.
    var pendingEnd: PendingLiveEnd?

    func isEnding(_ game: Game) -> Bool { endingGameIDs.contains(game.id) }
    func isEnding(_ practice: Practice) -> Bool { endingPracticeIDs.contains(practice.id) }

    // MARK: - End

    /// Ask before ending — ending finalizes stats, so it's never one tap from a
    /// card or the tab-bar accessory. `isGolf` comes from the caller, which knows
    /// the profile-sport fallback for a seasonless game.
    func requestEnd(_ game: Game, isGolf: Bool) {
        pendingEnd = PendingLiveEnd(
            target: .game(game),
            title: LiveEndPrompt.title(isGolf: isGolf),
            button: LiveEndPrompt.button(isGolf: isGolf),
            message: LiveEndPrompt.message(isGolf: isGolf)
        )
    }

    func requestEnd(_ practice: Practice) {
        let isRange = practice.practiceType == PracticeType.rangeSession.rawValue
        pendingEnd = PendingLiveEnd(
            target: .practice(practice),
            title: LiveEndPrompt.practiceTitle(isRangeSession: isRange),
            button: LiveEndPrompt.practiceButton(isRangeSession: isRange),
            message: LiveEndPrompt.practiceMessage
        )
    }

    /// Takes the dialog's own value rather than re-reading `pendingEnd`: the
    /// dialog's dismissal can clear that before the button action runs, which
    /// would make End a silent no-op.
    func confirmPendingEnd(_ pending: PendingLiveEnd, in modelContext: ModelContext) {
        pendingEnd = nil
        switch pending.target {
        case .game(let game):
            // Held for the whole dialog: a sync remote-delete or athlete delete
            // may have removed it, and endGame reads game.id before its own
            // guard — a deleted @Model read traps (build 177/185).
            guard !game.isDeleted, game.modelContext != nil else { return }
            endGame(game, in: modelContext)
        case .practice(let practice):
            guard !practice.isDeleted, practice.modelContext != nil else { return }
            endPractice(practice, in: modelContext)
        }
    }

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
            // The Task hop is a runloop turn: a sync remote-delete or athlete
            // delete can land in it, and end() writes `isLive` first — writing a
            // deleted @Model traps. Same guard PracticeService.deleteDeep uses.
            guard !game.isDeleted, game.modelContext != nil else { return }
            // Already ended elsewhere while the confirmation was up — a second
            // end() would re-fire the milestone/banner/clip-nudge effects.
            guard game.isLive else { return }
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
            // See endGame: guard the post-hop write against a deleted model.
            guard !practice.isDeleted, practice.modelContext != nil else { return }
            guard practice.isLive else { return }
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
            // The permission prompt can sit on screen indefinitely; don't hand the
            // recorder a game that was deleted while it was up.
            guard !game.isDeleted, game.modelContext != nil else { return }
            recordingGame = game
        }
    }

    /// Recorder bound to a live practice, so swings attribute to that session.
    func recordInto(practice: Practice, context: String) {
        Task { @MainActor in
            guard await ensureCapturePermission(context: context) else { return }
            // See recordInto(game:): re-validate after the permission await.
            guard !practice.isDeleted, practice.modelContext != nil else { return }
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
