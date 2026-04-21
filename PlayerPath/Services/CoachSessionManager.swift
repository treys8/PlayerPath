//
//  CoachSessionManager.swift
//  PlayerPath
//
//  Manages live instruction sessions for coaches.
//  Handles session CRUD, clip tracking, and state transitions.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import os

private let sessionLog = Logger(subsystem: "com.playerpath.app", category: "CoachSessions")

@MainActor
@Observable
final class CoachSessionManager {
    static let shared = CoachSessionManager()

    private(set) var activeSession: CoachSession?
    private(set) var sessions: [CoachSession] = []
    private(set) var scheduledSessions: [CoachSession] = []
    private(set) var isLoading = false

    private let db = Firestore.firestore()
    private var activeListener: ListenerRegistration?
    private var reviewingListener: ListenerRegistration?
    private var listeningCoachID: String?
    private var latestLive: CoachSession?
    private var latestReviewing: CoachSession?
    /// Guards against duplicate uploads when `uploadClip` is invoked twice for the
    /// same source URL (UI race conditions, double-taps).
    private var inflightUploadSources: Set<URL> = []
    private init() {}

    // MARK: - Helpers

    private func athleteData(
        from athletes: [(athleteID: String, athleteName: String, folderID: String)]
    ) -> (ids: [String], names: [String: String], folders: [String: String]) {
        (
            athletes.map(\.athleteID),
            Dictionary(uniqueKeysWithValues: athletes.map { ($0.athleteID, $0.athleteName) }),
            Dictionary(uniqueKeysWithValues: athletes.map { ($0.athleteID, $0.folderID) })
        )
    }

    /// Validates the coach hasn't exceeded their tier's athlete limit.
    private func enforceAthleteLimit(coachID: String, authManager: ComprehensiveAuthManager) async throws {
        let limit = authManager.coachAthleteLimit
        guard limit != Int.max else { return }
        let connectedCount = await SubscriptionGate.fullConnectedAthleteCount(coachID: coachID)
        if connectedCount > limit {
            throw CoachSessionError.athleteLimitExceeded(limit: limit)
        }
    }

    // MARK: - Session Lifecycle

    /// Transitions session from live to reviewing.
    func endSession(sessionID: String) async throws {
        try await db.collection(FC.coachSessions).document(sessionID).updateData([
            "status": SessionStatus.reviewing.rawValue,
            "endedAt": FieldValue.serverTimestamp()
        ])
        activeSession?.status = .reviewing
        activeSession?.endedAt = Date()
        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx].status = .reviewing
            sessions[idx].endedAt = Date()
        }
    }

    /// Marks session as completed.
    func completeSession(sessionID: String) async throws {
        try await db.collection(FC.coachSessions).document(sessionID).updateData([
            "status": SessionStatus.completed.rawValue,
            "endedAt": FieldValue.serverTimestamp()
        ])
        activeSession = nil
        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx].status = .completed
            sessions[idx].endedAt = Date()
        }
    }

    /// Ends any active session that involves the given folder (e.g., on access revocation).
    func endSessionIfActive(forFolderID folderID: String) async {
        guard let session = activeSession,
              session.status.isActive,
              let sessionID = session.id,
              session.folderIDs.values.contains(folderID) else { return }
        do {
            try await endSession(sessionID: sessionID)
        } catch {
            sessionLog.error("Failed to end session: \(error.localizedDescription)")
        }
    }

    /// Moves abandoned live sessions (older than 24 hours) to `.reviewing` so any clips
    /// captured before abandonment remain reviewable. The coach can explicitly `.complete`
    /// from the dashboard after reviewing. Previously jumped straight to `.completed`,
    /// losing the review opportunity.
    func cleanupAbandonedSessions() async {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        for session in sessions where session.status == .live {
            guard let startedAt = session.startedAt, startedAt < cutoff, let sessionID = session.id else { continue }
            do {
                try await endSession(sessionID: sessionID)
            } catch {
                sessionLog.error("Failed to cleanup abandoned session: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Scheduled Sessions

    /// Creates a session. If `scheduledDate` is provided, it's shown on the card;
    /// otherwise the session is ready to go live immediately.
    /// Validates athlete limit to prevent creating beyond the coach's tier.
    func scheduleSession(
        coachID: String,
        coachName: String,
        athletes: [(athleteID: String, athleteName: String, folderID: String)],
        scheduledDate: Date? = nil,
        notes: String?,
        authManager: ComprehensiveAuthManager
    ) async throws -> String {
        try await enforceAthleteLimit(coachID: coachID, authManager: authManager)

        let (athleteIDs, athleteNames, folderIDs) = athleteData(from: athletes)

        var data: [String: Any] = [
            "coachID": coachID,
            "coachName": coachName,
            "athleteIDs": athleteIDs,
            "athleteNames": athleteNames,
            "folderIDs": folderIDs,
            "status": SessionStatus.scheduled.rawValue,
            "clipCount": 0
        ]
        if let scheduledDate {
            data["scheduledDate"] = Timestamp(date: scheduledDate)
        }
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["notes"] = notes
        }

        let docRef = try await db.collection(FC.coachSessions).addDocument(data: data)

        let session = CoachSession(
            id: docRef.documentID,
            coachID: coachID,
            coachName: coachName,
            athleteIDs: athleteIDs,
            athleteNames: athleteNames,
            folderIDs: folderIDs,
            status: .scheduled,
            startedAt: nil,
            clipCount: 0,
            scheduledDate: scheduledDate,
            notes: notes
        )
        scheduledSessions.append(session)
        scheduledSessions.sort { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }

        return docRef.documentID
    }

    /// Transitions a reviewing session back to live so the coach can record more clips
    /// in the same session. Resets startedAt so the LiveSessionCard timer reflects the
    /// new segment, clears endedAt.
    func resumeReviewingSession(sessionID: String) async throws {
        let now = Date()
        try await db.collection(FC.coachSessions).document(sessionID).updateData([
            "status": SessionStatus.live.rawValue,
            "startedAt": FieldValue.serverTimestamp(),
            "endedAt": FieldValue.delete()
        ])

        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx].status = .live
            sessions[idx].startedAt = now
            sessions[idx].endedAt = nil
            activeSession = sessions[idx]
        } else if activeSession?.id == sessionID {
            activeSession?.status = .live
            activeSession?.startedAt = now
            activeSession?.endedAt = nil
        }
    }

    /// Transitions a scheduled session to live, ending any existing live session first.
    func startScheduledSession(sessionID: String) async throws {
        // End any existing live session to enforce one-active-session constraint
        if let existing = activeSession, let existingID = existing.id, existing.status == .live {
            try await endSession(sessionID: existingID)
        }

        let now = Date()
        try await db.collection(FC.coachSessions).document(sessionID).updateData([
            "status": SessionStatus.live.rawValue,
            "startedAt": FieldValue.serverTimestamp()
        ])

        if let idx = scheduledSessions.firstIndex(where: { $0.id == sessionID }) {
            var session = scheduledSessions.remove(at: idx)
            session.status = .live
            session.startedAt = now
            activeSession = session
            sessions.insert(session, at: 0)
        }
    }

    /// Cancels a scheduled session (deletes it).
    func cancelScheduledSession(sessionID: String) async throws {
        try await db.collection(FC.coachSessions).document(sessionID).delete()
        scheduledSessions.removeAll { $0.id == sessionID }
    }

    /// Updates the session's notes field. Pass nil or empty to clear.
    func updateSessionNotes(sessionID: String, notes: String?) async throws {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        var updateData: [String: Any] = [:]
        if let trimmed, !trimmed.isEmpty {
            updateData["notes"] = trimmed
        } else {
            updateData["notes"] = FieldValue.delete()
        }
        try await db.collection(FC.coachSessions).document(sessionID).updateData(updateData)

        // Update local state
        if let idx = scheduledSessions.firstIndex(where: { $0.id == sessionID }) {
            scheduledSessions[idx].notes = trimmed
        }
        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx].notes = trimmed
        }
        if activeSession?.id == sessionID {
            activeSession?.notes = trimmed
        }
    }

    /// Increments the clip count for the active session. Local state only bumps after
    /// the Firestore write succeeds — otherwise cross-device counts drift.
    func incrementClipCount(sessionID: String) async {
        do {
            try await db.collection(FC.coachSessions).document(sessionID).updateData([
                "clipCount": FieldValue.increment(Int64(1))
            ])
            if activeSession?.id == sessionID {
                activeSession?.clipCount += 1
            }
            if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[idx].clipCount += 1
            }
        } catch {
            sessionLog.error("Failed to increment clip count: \(error.localizedDescription)")
            // Deliberately skip local bump — listener / next fetch will converge.
        }
    }

    // MARK: - Queries

    /// Fetches all sessions for this coach. Uses three single-status queries
    /// merged in memory — avoids the composite index required by
    /// `isNotEqualTo + order(by: status)` which previously caused silent failures
    /// when the index hadn't been deployed.
    func fetchSessions(coachID: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Run the four status queries concurrently — each is an independent
            // Firestore round-trip, so this cuts cold-start latency roughly 4×.
            async let liveFetch = fetchSessionsWithStatus(coachID: coachID, status: .live, limit: 10)
            async let reviewingFetch = fetchSessionsWithStatus(coachID: coachID, status: .reviewing, limit: 20)
            async let completedFetch = fetchSessionsWithStatus(
                coachID: coachID,
                status: .completed,
                limit: 50,
                orderByStartedAtDescending: true
            )
            async let scheduledFetch = fetchSessionsWithStatus(
                coachID: coachID,
                status: .scheduled,
                limit: 20,
                orderByScheduledDateAscending: true
            )
            let (live, reviewing, completed, scheduled) = try await (liveFetch, reviewingFetch, completedFetch, scheduledFetch)

            // Active sessions first (newest startedAt), then completed.
            let active = (live + reviewing).sorted {
                ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
            }
            sessions = active + completed
            scheduledSessions = scheduled

            activeSession = sessions.first(where: { $0.status.isActive })

            await cleanupAbandonedSessions()
        } catch {
            sessionLog.error("Failed to fetch sessions: \(error.localizedDescription)")
        }
    }

    private func fetchSessionsWithStatus(
        coachID: String,
        status: SessionStatus,
        limit: Int,
        orderByStartedAtDescending: Bool = false,
        orderByScheduledDateAscending: Bool = false
    ) async throws -> [CoachSession] {
        var query: Query = db.collection(FC.coachSessions)
            .whereField("coachID", isEqualTo: coachID)
            .whereField("status", isEqualTo: status.rawValue)

        if orderByStartedAtDescending {
            query = query.order(by: "startedAt", descending: true)
        } else if orderByScheduledDateAscending {
            query = query.order(by: "scheduledDate", descending: false)
        }

        let snap = try await query.limit(to: limit).getDocuments()
        return snap.documents.compactMap { doc in
            do {
                var session = try doc.data(as: CoachSession.self)
                session.id = doc.documentID
                return session
            } catch {
                sessionLog.error("Failed to decode session \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// Reloads a single session from Firestore and merges it into local state.
    /// Returns the refreshed session, or nil if the doc no longer exists.
    /// Used by resume-session flows to verify status before presenting UI.
    @discardableResult
    func refreshSession(id: String) async throws -> CoachSession? {
        let snap = try await db.collection(FC.coachSessions).document(id).getDocument()
        guard snap.exists else {
            // Session was deleted — remove from local state
            sessions.removeAll { $0.id == id }
            scheduledSessions.removeAll { $0.id == id }
            if activeSession?.id == id { activeSession = nil }
            return nil
        }
        var session = try snap.data(as: CoachSession.self)
        session.id = snap.documentID

        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx] = session
        } else if session.status != .scheduled {
            sessions.insert(session, at: 0)
        }
        if session.status == .scheduled {
            if let idx = scheduledSessions.firstIndex(where: { $0.id == id }) {
                scheduledSessions[idx] = session
            }
        } else {
            scheduledSessions.removeAll { $0.id == id }
        }
        if session.status.isActive {
            activeSession = session
        } else if activeSession?.id == id {
            activeSession = nil
        }
        return session
    }

    /// Starts real-time listeners for this coach's active (live + reviewing) sessions.
    /// Two single-field queries (no composite index) resolve independently; the combined
    /// `activeSession` prefers live > reviewing. Keeps the dashboard in sync across
    /// devices when a session is ended/resumed elsewhere.
    func startListeningActiveSession(coachID: String) {
        if activeListener != nil, listeningCoachID == coachID { return }
        stopListeningActiveSession()
        listeningCoachID = coachID

        activeListener = attachStatusListener(coachID: coachID, status: .live) { [weak self] session in
            guard let self else { return }
            self.latestLive = session
            self.resolveActiveSession()
        }

        reviewingListener = attachStatusListener(coachID: coachID, status: .reviewing) { [weak self] session in
            guard let self else { return }
            self.latestReviewing = session
            self.resolveActiveSession()
        }
    }

    private func attachStatusListener(
        coachID: String,
        status: SessionStatus,
        onUpdate: @escaping @MainActor (CoachSession?) -> Void
    ) -> ListenerRegistration {
        return db.collection(FC.coachSessions)
            .whereField("coachID", isEqualTo: coachID)
            .whereField("status", isEqualTo: status.rawValue)
            .limit(to: 1)
            .addSnapshotListener { snapshot, error in
                if let error {
                    sessionLog.warning("\(status.rawValue, privacy: .public) session listener error: \(error.localizedDescription)")
                    return
                }
                guard let snapshot else { return }
                let session: CoachSession? = snapshot.documents.first.flatMap { doc in
                    do {
                        var s = try doc.data(as: CoachSession.self)
                        s.id = doc.documentID
                        return s
                    } catch {
                        sessionLog.warning("Failed to decode \(status.rawValue, privacy: .public) session \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                }
                Task { @MainActor in
                    onUpdate(session)
                }
            }
    }

    /// Reconciles `activeSession` from the two status listeners. Live wins over reviewing;
    /// nil only when both are empty.
    private func resolveActiveSession() {
        let winner = latestLive ?? latestReviewing

        if let winner {
            if let idx = sessions.firstIndex(where: { $0.id == winner.id }) {
                sessions[idx] = winner
            } else {
                sessions.insert(winner, at: 0)
            }
            activeSession = winner
        } else {
            // Both snapshots empty — no active session on server
            activeSession = nil
        }
    }

    func stopListeningActiveSession() {
        activeListener?.remove()
        activeListener = nil
        reviewingListener?.remove()
        reviewingListener = nil
        latestLive = nil
        latestReviewing = nil
        listeningCoachID = nil
    }

    // MARK: - Clip Upload

    /// Enqueues a recorded clip for background upload via UploadQueueManager.
    /// The queue handles retries, background task support, and persistence.
    ///
    /// Guards:
    ///   - Dedup: same source URL queued more than once returns silently.
    ///   - Permission: verifies the coach still has upload permission on the folder.
    ///     If not (access revoked mid-session), the clip is moved to
    ///     `coach_failed_uploads/` and a recovery notification is posted — not silently
    ///     dropped to the queue where it would fail and eventually be discarded.
    func uploadClip(
        videoURL: URL,
        folderID: String,
        sessionID: String,
        coachID: String,
        coachName: String
    ) async {
        // Dedup — prevents duplicate uploads from a UI race
        guard !inflightUploadSources.contains(videoURL) else {
            sessionLog.warning("Duplicate uploadClip call for \(videoURL.lastPathComponent, privacy: .public) — ignoring")
            return
        }
        inflightUploadSources.insert(videoURL)
        defer { inflightUploadSources.remove(videoURL) }

        // Permission pre-check — avoid silent loss when access was revoked.
        let hasUploadAccess = await canUploadToFolder(folderID: folderID, coachID: coachID)

        // Verify session status (non-blocking — we still want the clip saved locally)
        do {
            let sessionDoc = try await db.collection(FC.coachSessions).document(sessionID).getDocument()
            let status = sessionDoc.data()?["status"] as? String
            if status != SessionStatus.live.rawValue && status != SessionStatus.reviewing.rawValue {
                sessionLog.warning("Session not active during clip upload — enqueuing anyway")
            }
        } catch {
            sessionLog.error("Failed to check session status: \(error.localizedDescription)")
        }

        let dateStr = Date().formatted(.iso8601.year().month().day())
        let fileName = "instruction_\(dateStr)_\(UUID().uuidString.prefix(8)).mov"

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        // If the coach lost access, route to failed_uploads instead of the queue.
        // The clip stays on disk so the coach can recover it if access is restored.
        let targetDir: URL = hasUploadAccess
            ? documentsURL.appendingPathComponent("coach_pending_uploads", isDirectory: true)
            : documentsURL.appendingPathComponent("coach_failed_uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let stablePath = targetDir.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: stablePath.path) {
                try FileManager.default.removeItem(at: stablePath)
            }
            try FileManager.default.copyItem(at: videoURL, to: stablePath)
        } catch {
            sessionLog.error("Failed to copy clip to stable path: \(error.localizedDescription)")
            return
        }

        try? FileManager.default.removeItem(at: videoURL)

        guard hasUploadAccess else {
            sessionLog.warning("Coach lacks upload permission on folder \(folderID, privacy: .public) — saved to failed_uploads, notifying coach")
            await ActivityNotificationService.shared.postClipUploadFailedPermissionNotification(
                coachUserID: coachID,
                folderID: folderID,
                fileName: fileName
            )
            return
        }

        UploadQueueManager.shared.enqueueCoachUpload(
            fileName: fileName,
            filePath: stablePath.path,
            folderID: folderID,
            coachID: coachID,
            coachName: coachName,
            sessionID: sessionID,
            priority: .normal
        )
    }

    /// Verifies the coach currently has upload permission on the target shared folder.
    /// Returns false on any error so we err on the side of surfacing a recovery path.
    private func canUploadToFolder(folderID: String, coachID: String) async -> Bool {
        do {
            let snap = try await db.collection(FC.sharedFolders).document(folderID).getDocument()
            guard let data = snap.data() else { return false }
            let sharedCoachIDs = data["sharedWithCoachIDs"] as? [String] ?? []
            guard sharedCoachIDs.contains(coachID) else { return false }
            let permissions = data["permissions"] as? [String: [String: Any]] ?? [:]
            let coachPerms = permissions[coachID] ?? [:]
            return (coachPerms["canUpload"] as? Bool) == true
        } catch {
            sessionLog.error("canUploadToFolder failed: \(error.localizedDescription)")
            return false
        }
    }


}

// MARK: - Errors

enum CoachSessionError: LocalizedError {
    case athleteLimitExceeded(limit: Int)

    var errorDescription: String? {
        switch self {
        case .athleteLimitExceeded(let limit):
            return "Your plan supports up to \(limit) athletes. Upgrade to add more."
        }
    }
}
