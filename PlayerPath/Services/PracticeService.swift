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

    // MARK: - Deep Delete

    /// Delete a practice and everything hanging off it, locally and in Firestore.
    /// Mirrors `GameService.deleteGameDeep`; returns whether the local delete
    /// committed so callers can gate their haptics/dismiss on it.
    ///
    /// Replaces the old view-level delete, which passed `user.id.uuidString`
    /// (the local SwiftData UUID) as the Firestore user key. Practice docs live
    /// under `users/{firebaseAuthUid}/`, so that write never landed and the next
    /// sync re-downloaded the still-live doc — deleted practices came back.
    @discardableResult
    func deleteDeep(_ practice: Practice) async -> Bool {
        // Callers reach this through a Task, so a runloop hop separates the tap
        // from the first property read — long enough for a sync remote-deletion
        // pass (or a second swipe on a stale row) to invalidate the model. Reading
        // any property of a deleted @Model traps, so bail instead.
        guard !practice.isDeleted, practice.modelContext != nil else {
            logger.info("Skipped practice delete — model already removed")
            return false
        }

        // MARK: Capture primitives before anything is deleted.
        // Strict `firebaseAuthUid` with no `?? id.uuidString` fallback: that
        // fallback is exactly the bug this method exists to fix. Signed out ⇒
        // no remote calls, and the Auth-onDelete recursive sweep is the backstop.
        let firestoreId = practice.firestoreId
        let userId = practice.athlete?.user?.firebaseAuthUid
        let practiceAthlete = practice.athlete
        let practiceID = practice.id

        // Hole docs are keyed by hole number, and `deletePracticeHoleScore` uses
        // updateData (throws on a missing doc), so only rows that actually
        // uploaded — `firestoreId` is set post-upload — are worth tombstoning.
        let allHoles: [HoleScore] = practice.holeScores ?? []
        let syncedHoleNumbers: [Int] = allHoles
            .filter { $0.firestoreId != nil }
            .map { $0.holeNumber }

        // Shot docs live under the hole doc, keyed by the shot UUID. Rounds that
        // never tracked shot-by-shot have no Shot rows, so this is empty for them.
        var syncedShotRefs: [(holeNumber: Int, shotId: String)] = []
        for hole in allHoles {
            let holeNumber = hole.holeNumber
            for shot in (hole.shots ?? []) where shot.firestoreId != nil {
                syncedShotRefs.append((holeNumber: holeNumber, shotId: shot.id.uuidString))
            }
        }

        // Note docs live under the practice doc. They'd be orphaned by the
        // practice tombstone alone, and if that tombstone ever fails the notes
        // are what re-materialize the practice on the next download.
        let syncedNoteIDs: [String] = (practice.notes ?? []).compactMap(\.firestoreId)

        // Reels carry a denormalized `practiceID` (no SwiftData relationship), so
        // they need a flat fetch. Capture doc IDs for the remote tombstone, then
        // hard-delete the local rows. Mirrors GameService.deleteGameDeep.
        var reelDocIDsToSoftDelete: [String] = []
        do {
            let allReels = try modelContext.fetch(FetchDescriptor<HighlightReel>())
            let matchingReels = allReels.filter { $0.practiceID == practiceID }
            reelDocIDsToSoftDelete = matchingReels.compactMap(\.firestoreId)
            for reel in matchingReels {
                modelContext.delete(reel)
            }
        } catch {
            logger.error("Failed to fetch HighlightReels for practice cascade delete: \(error.localizedDescription)")
        }

        // MARK: Local cascade.
        // cleanupReels: false — the reels were just hard-deleted above, so
        // per-clip reel stripping would be wasted work.
        for clip in practice.videoClips ?? [] {
            clip.delete(in: modelContext, cleanupReels: false)
        }
        // Photos were never cascaded before this method existed: the inverse
        // nullifies, so they survived as loose photos in the Journal feed with
        // their local files and Storage objects intact.
        for photo in practice.photos ?? [] {
            photo.delete(in: modelContext)
        }
        for note in practice.notes ?? [] {
            modelContext.delete(note)
        }
        // Shot rows ride along via HoleScore.shots' .cascade rule.
        for hole in practice.holeScores ?? [] {
            modelContext.delete(hole)
        }

        modelContext.delete(practice)

        do {
            try modelContext.save()
        } catch {
            // The clip/photo deletes above already removed local files and
            // tombstoned their cloud docs, so this isn't a clean no-op — the
            // practice survives with its media gone. Surface it as such rather
            // than letting the caller's error haptic imply nothing happened.
            logger.error("Failed to save practice deletion: \(error.localizedDescription)")
            ErrorHandlerService.shared.handle(
                error,
                context: "PracticeService.deleteDeep — partial delete: media removed but practice not deleted",
                showAlert: false
            )
            return false
        }

        // Cancel reminders only AFTER the delete is committed — bailing out above
        // leaves the practice alive, and a live practice with cancelled reminders
        // would never nudge again. All identifiers are captured primitives.
        GameAlertService.shared.cancelEndPracticeReminder(forID: practiceID)
        ClipTaggingReminderService.shared.cancelNudge(eventID: practiceID)

        // Practices don't roll up into athlete statistics themselves, but their
        // clips carry play results that do — recalculate like the game path.
        if let athlete = practiceAthlete {
            do {
                try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext, skipSave: true)
                try modelContext.save()
            } catch {
                logger.error("Failed to recalculate statistics after practice deletion: \(error.localizedDescription)")
            }
        }

        logger.info("Deleted practice and related data successfully")

        // MARK: Remote soft-deletes (fire-and-forget, retried).
        // Practice-scoped docs: the practice itself, then its hole and shot
        // subcollection docs so cross-device sync can't resurrect them.
        if let firestoreId, let userId {
            Task {
                await retryAsync {
                    try await FirestoreManager.shared.deletePractice(userId: userId, practiceId: firestoreId)
                }
                for holeNumber in syncedHoleNumbers {
                    await retryAsync {
                        try await FirestoreManager.shared.deletePracticeHoleScore(
                            userId: userId,
                            practiceFirestoreId: firestoreId,
                            holeNumber: holeNumber
                        )
                    }
                }
                for ref in syncedShotRefs {
                    await retryAsync {
                        try await FirestoreManager.shared.deletePracticeShot(
                            userId: userId,
                            practiceFirestoreId: firestoreId,
                            holeNumber: ref.holeNumber,
                            shotId: ref.shotId
                        )
                    }
                }
                for noteId in syncedNoteIDs {
                    await retryAsync {
                        try await FirestoreManager.shared.deletePracticeNote(
                            userId: userId,
                            practiceFirestoreId: firestoreId,
                            noteId: noteId
                        )
                    }
                }
            }
        }

        // Reels are keyed to the user, not the practice doc, so a practice that
        // never synced can still own synced reels — guard on userId only.
        if let userId, !reelDocIDsToSoftDelete.isEmpty {
            Task {
                for reelId in reelDocIDsToSoftDelete {
                    await retryAsync {
                        try await FirestoreManager.shared.deleteHighlightReel(userId: userId, reelId: reelId)
                    }
                }
            }
        }

        return true
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
