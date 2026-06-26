import Foundation
import SwiftData
import os.log

/// Lifecycle for golf practices that can be the live dashboard activity
/// (practice rounds and range sessions). Mirrors the live-game half of
/// `GameService`: starting one ends any other live golf activity, ending one
/// clears the flags. Baseball practices never go live, so they never reach
/// here.
@MainActor
final class PracticeService {

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.playerpath.app", category: "PracticeService")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// End a live practice. Clears the live flags; no stats recalc (practices
    /// don't roll up into athlete statistics the way games do). Going live
    /// happens inline at creation in AddPracticeView, mirroring
    /// GameService.createGame — there's no separate start() here.
    func end(_ practice: Practice) async {
        practice.isLive = false
        practice.liveStartDate = nil
        practice.needsSync = true
        GameAlertService.shared.cancelEndPracticeReminder(for: practice)

        // Snapshot to plain values BEFORE the save/await for the clip-tagging
        // nudge — a concurrent delete must not invalidate the model mid-flight.
        // Golf clips are tagged by `club`, so `isTagged` already covers golf
        // round parity (a no-club clip counts as untagged).
        let endedPracticeID = practice.id
        let untaggedClipCount = (practice.videoClips ?? []).filter {
            !$0.isTagged && !$0.isDeletedRemotely && $0.sourceCoachVideoID == nil
        }.count

        // Practices don't roll up into athlete statistics, so there is no
        // milestone diff here — only the clip-tagging nudge (parity with
        // GameService.end, which nudges only inside its successful save).
        // Practices are golf-only in practice, so "round".
        if await save(practice, action: "end") {
            await ClipTaggingReminderService.shared.scheduleIfNeeded(
                eventID: endedPracticeID,
                untaggedCount: untaggedClipCount,
                eventNoun: "round"
            )
        }
    }

    @discardableResult
    private func save(_ practice: Practice, action: String) async -> Bool {
        let userForSync = practice.athlete?.user
        do {
            try modelContext.save()
            // Mirror GameService.end()'s `.gameEnded` post: announce the ended
            // event after the save commits so the highlight-reel banner can read
            // a settled relationship graph. End-only so a future save() caller
            // doesn't fire it.
            if action == "end" {
                NotificationCenter.default.post(name: .practiceEnded, object: practice)
            }
            Task {
                guard let user = userForSync else { return }
                do {
                    try await SyncCoordinator.shared.syncPractices(for: user)
                } catch {
                    self.logger.error("Sync after practice \(action) failed: \(error.localizedDescription)")
                }
            }
            return true
        } catch {
            logger.error("Failed to save practice \(action): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Single-live golf invariant

    /// Ends every live golf activity for the athlete except an optional
    /// in-flight game/practice. Called when a golf practice goes live inline at
    /// creation (`AddPracticeView.save`); it ends any live golf game as well as
    /// any other live practice, so the "one live golf activity at a time" rule
    /// spans games and practices. (The game-start side enforces the same
    /// invariant through `GameService`'s own inline logic + its `endLivePractices`
    /// helper — it does NOT route through here.) Flips flags + marks dirty; the
    /// caller is responsible for saving.
    static func endAllOtherLiveGolf(for athlete: Athlete,
                                    exceptGame: Game? = nil,
                                    exceptPractice: Practice? = nil) {
        for game in (athlete.games ?? [])
        where game.isLive && game.id != exceptGame?.id && game.season?.sport == .golf {
            game.isLive = false
            game.liveStartDate = nil
            game.needsSync = true
            GameAlertService.shared.cancelEndGameReminder(for: game)
        }
        // Practices only ever go live on the golf side, so no sport filter.
        for practice in (athlete.practices ?? [])
        where practice.isLive && practice.id != exceptPractice?.id {
            practice.isLive = false
            practice.liveStartDate = nil
            practice.needsSync = true
            GameAlertService.shared.cancelEndPracticeReminder(for: practice)
        }
    }
}
