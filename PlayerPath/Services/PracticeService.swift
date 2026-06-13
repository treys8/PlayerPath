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

        await save(practice, action: "end")
    }

    private func save(_ practice: Practice, action: String) async {
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
        } catch {
            logger.error("Failed to save practice \(action): \(error.localizedDescription)")
        }
    }

    // MARK: - Single-live golf invariant

    /// Ends every live golf activity for the athlete except an optional
    /// in-flight game/practice. Used by both `PracticeService.startLive` and
    /// `GameService`'s golf start paths so the "one live golf activity at a
    /// time" rule spans games and practices. Flips flags + marks dirty; the
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
