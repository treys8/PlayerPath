//
//  CoachSessionManager.swift
//  PlayerPath
//
//  Manages live instruction sessions for coaches.
//  Handles session CRUD, clip tracking, and state transitions.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import os

private let sessionLog = Logger(subsystem: "com.playerpath.app", category: "CoachSessions")

@MainActor
@Observable
class CoachSessionManager {
    static let shared = CoachSessionManager()

    var activeSession: CoachSession?
    var sessions: [CoachSession] = []
    var scheduledSessions: [CoachSession] = []
    var isLoading = false

    private let db = Firestore.firestore()
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
        NotificationCenter.default.post(name: .sessionEnded, object: sessionID)
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

    /// Auto-ends abandoned sessions older than 24 hours.
    func cleanupAbandonedSessions() async {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        for session in sessions where session.status == .live {
            guard let startedAt = session.startedAt, startedAt < cutoff, let sessionID = session.id else { continue }
            do {
                try await completeSession(sessionID: sessionID)
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

        NotificationCenter.default.post(name: .sessionScheduled, object: docRef.documentID)
        return docRef.documentID
    }

    /// Transitions a scheduled session to live, ending any existing live session first.
    func startScheduledSession(sessionID: String) async throws {
        // End any existing live session to enforce one-active-session constraint
        if let existing = activeSession, let existingID = existing.id, existing.status == .live {
            try await endSession(sessionID: existingID)
        }

        try await db.collection(FC.coachSessions).document(sessionID).updateData([
            "status": SessionStatus.live.rawValue,
            "startedAt": FieldValue.serverTimestamp()
        ])

        if let idx = scheduledSessions.firstIndex(where: { $0.id == sessionID }) {
            var session = scheduledSessions.remove(at: idx)
            session.status = .live
            activeSession = session
            sessions.insert(session, at: 0)
        }

        NotificationCenter.default.post(name: .sessionBecameLive, object: sessionID)
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

    /// Increments the clip count for the active session.
    func incrementClipCount(sessionID: String) async {
        do {
            try await db.collection(FC.coachSessions).document(sessionID).updateData([
                "clipCount": FieldValue.increment(Int64(1))
            ])
            activeSession?.clipCount += 1
            if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[idx].clipCount += 1
            }
        } catch {
            sessionLog.error("Failed to increment clip count: \(error.localizedDescription)")
        }
    }

    // MARK: - Queries

    /// Fetches all sessions for this coach, newest first.
    func fetchSessions(coachID: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Run both queries sequentially — async let can crash the Swift runtime
            // if the parent task is cancelled mid-flight (asyncLet_finish_after_task_completion)
            let started = try await db.collection(FC.coachSessions)
                .whereField("coachID", isEqualTo: coachID)
                .whereField("status", isNotEqualTo: SessionStatus.scheduled.rawValue)
                .order(by: "status")
                .order(by: "startedAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            let scheduled = try await db.collection(FC.coachSessions)
                .whereField("coachID", isEqualTo: coachID)
                .whereField("status", isEqualTo: SessionStatus.scheduled.rawValue)
                .order(by: "scheduledDate", descending: false)
                .limit(to: 20)
                .getDocuments()

            sessions = started.documents.compactMap { doc in
                do {
                    var session = try doc.data(as: CoachSession.self)
                    session.id = doc.documentID
                    return session
                } catch {
                    sessionLog.error("Failed to decode session \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }

            scheduledSessions = scheduled.documents.compactMap { doc in
                do {
                    var session = try doc.data(as: CoachSession.self)
                    session.id = doc.documentID
                    return session
                } catch {
                    sessionLog.error("Failed to decode scheduled session \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }

            // Detect if there's an active (live/reviewing) session
            activeSession = sessions.first(where: { $0.status.isActive })

            // Auto-end abandoned sessions (live for > 24 hours)
            await cleanupAbandonedSessions()
        } catch {
            sessionLog.error("Failed to fetch sessions: \(error.localizedDescription)")
        }
    }

    // MARK: - Clip Upload

    /// Enqueues a recorded clip for background upload via UploadQueueManager.
    /// The queue handles retries, background task support, and persistence.
    func uploadClip(
        videoURL: URL,
        folderID: String,
        sessionID: String,
        coachID: String,
        coachName: String
    ) async {
        // Verify session is still live before uploading — clips to completed sessions may be missed
        do {
            let sessionDoc = try await db.collection(FC.coachSessions).document(sessionID).getDocument()
            let status = sessionDoc.data()?["status"] as? String
            if status != SessionStatus.live.rawValue && status != SessionStatus.reviewing.rawValue {
                sessionLog.warning("Session not active during clip upload — enqueuing anyway")
                // Don't abort — the clip is recorded locally. Enqueue it anyway so it's not lost.
            }
        } catch {
            // Network failure checking session status — proceed with upload anyway
            sessionLog.error("Failed to check session status: \(error.localizedDescription)")
        }

        let dateStr = Date().formatted(.iso8601.year().month().day())
        let fileName = "instruction_\(dateStr)_\(UUID().uuidString.prefix(8)).mov"

        // Move the video to a stable Documents path so it survives app backgrounding.
        // The queue will read from this path later.
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let coachUploadsDir = documentsURL.appendingPathComponent("coach_pending_uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: coachUploadsDir, withIntermediateDirectories: true)
        let stablePath = coachUploadsDir.appendingPathComponent(fileName)

        do {
            // Copy instead of move in case the source is still referenced
            if FileManager.default.fileExists(atPath: stablePath.path) {
                try FileManager.default.removeItem(at: stablePath)
            }
            try FileManager.default.copyItem(at: videoURL, to: stablePath)
        } catch {
            sessionLog.error("Failed to copy clip for upload queue: \(error.localizedDescription)")
            return
        }

        // Remove the original recording now that we have a stable copy
        try? FileManager.default.removeItem(at: videoURL)

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


}

// MARK: - Errors

enum CoachSessionError: LocalizedError {
    case athleteLimitExceeded(limit: Int)
    case sessionNotActive

    var errorDescription: String? {
        switch self {
        case .athleteLimitExceeded(let limit):
            return "Your plan supports up to \(limit) athletes. Upgrade to add more."
        case .sessionNotActive:
            return "This session is no longer active."
        }
    }
}
