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

    /// Creates a new live session and returns its ID.
    /// Validates that the selected athletes don't exceed the coach's tier limit.
    func createSession(
        coachID: String,
        coachName: String,
        athletes: [(athleteID: String, athleteName: String, folderID: String)],
        authManager: ComprehensiveAuthManager
    ) async throws -> String {
        try await enforceAthleteLimit(coachID: coachID, authManager: authManager)

        let (athleteIDs, athleteNames, folderIDs) = athleteData(from: athletes)

        let data: [String: Any] = [
            "coachID": coachID,
            "coachName": coachName,
            "athleteIDs": athleteIDs,
            "athleteNames": athleteNames,
            "folderIDs": folderIDs,
            "status": SessionStatus.live.rawValue,
            "startedAt": FieldValue.serverTimestamp(),
            "clipCount": 0
        ]

        let docRef = try await db.collection(FC.coachSessions).addDocument(data: data)

        let session = CoachSession(
            id: docRef.documentID,
            coachID: coachID,
            coachName: coachName,
            athleteIDs: athleteIDs,
            athleteNames: athleteNames,
            folderIDs: folderIDs,
            status: .live,
            startedAt: Date(),
            clipCount: 0
        )
        activeSession = session
        sessions.insert(session, at: 0)

        return docRef.documentID
    }

    /// Convenience wrapper: resolves coach identity from authManager, creates a session,
    /// plays a success haptic, and handles errors. Returns `true` on success.
    func quickCreateSession(
        athletes: [(athleteID: String, athleteName: String, folderID: String)],
        authManager: ComprehensiveAuthManager
    ) async -> Bool {
        guard let coachID = authManager.userID else { return false }
        let coachName = authManager.userDisplayName ?? authManager.userEmail ?? "Coach"
        do {
            _ = try await createSession(
                coachID: coachID, coachName: coachName,
                athletes: athletes, authManager: authManager
            )
            Haptics.success()
            return true
        } catch {
            ErrorHandlerService.shared.handle(error, context: "CoachSessionManager.quickCreateSession")
            return false
        }
    }

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
            ErrorHandlerService.shared.handle(error, context: "CoachSessionManager.endSessionIfActive", showAlert: false)
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
                ErrorHandlerService.shared.handle(error, context: "CoachSessionManager.cleanupAbandoned", showAlert: false)
            }
        }
    }

    // MARK: - Scheduled Sessions

    /// Creates a scheduled session for a future date.
    /// Validates athlete limit to prevent scheduling beyond the coach's tier.
    func scheduleSession(
        coachID: String,
        coachName: String,
        athletes: [(athleteID: String, athleteName: String, folderID: String)],
        scheduledDate: Date,
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
            "scheduledDate": Timestamp(date: scheduledDate),
            "clipCount": 0
        ]
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

    /// Updates a scheduled session's date, athletes, or notes.
    func editScheduledSession(
        sessionID: String,
        newDate: Date? = nil,
        newAthletes: [(athleteID: String, athleteName: String, folderID: String)]? = nil,
        newNotes: String? = nil
    ) async throws {
        var updates: [String: Any] = [:]

        if let newDate {
            updates["scheduledDate"] = Timestamp(date: newDate)
        }
        if let newAthletes {
            let (ids, names, folders) = athleteData(from: newAthletes)
            updates["athleteIDs"] = ids
            updates["athleteNames"] = names
            updates["folderIDs"] = folders
        }
        if let newNotes {
            updates["notes"] = newNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FieldValue.delete() : newNotes
        }

        guard !updates.isEmpty else { return }
        try await db.collection(FC.coachSessions).document(sessionID).updateData(updates)

        if let idx = scheduledSessions.firstIndex(where: { $0.id == sessionID }) {
            if let newDate { scheduledSessions[idx].scheduledDate = newDate }
            if let newAthletes {
                let (ids, names, folders) = athleteData(from: newAthletes)
                scheduledSessions[idx].athleteIDs = ids
                scheduledSessions[idx].athleteNames = names
                scheduledSessions[idx].folderIDs = folders
            }
            if let newNotes { scheduledSessions[idx].notes = newNotes }
            scheduledSessions.sort { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
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
            ErrorHandlerService.shared.handle(error, context: "CoachSessionManager.incrementClipCount", showAlert: false)
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
                    ErrorHandlerService.shared.handle(error, context: "CoachSessionManager.decode(\(doc.documentID))", showAlert: false)
                    return nil
                }
            }

            scheduledSessions = scheduled.documents.compactMap { doc in
                do {
                    var session = try doc.data(as: CoachSession.self)
                    session.id = doc.documentID
                    return session
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "CoachSessionManager.decodeScheduled(\(doc.documentID))", showAlert: false)
                    return nil
                }
            }

            // Detect if there's an active (live/reviewing) session
            activeSession = sessions.first(where: { $0.status.isActive })

            // Auto-end abandoned sessions (live for > 24 hours)
            await cleanupAbandonedSessions()
        } catch {
            ErrorHandlerService.shared.handle(error, context: "CoachSessionManager.fetchSessions", showAlert: false)
        }
    }

    /// Fetches all clips for a session.
    func fetchSessionClips(sessionID: String) async throws -> [FirestoreVideoMetadata] {
        try await FirestoreManager.shared.fetchVideosBySession(sessionID: sessionID)
    }

    /// Clears the active session reference (e.g., after completing).
    func clearActiveSession() {
        activeSession = nil
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
                ErrorHandlerService.shared.handle(
                    CoachSessionError.sessionNotActive,
                    context: "CoachSessionManager.uploadClip.sessionCheck",
                    showAlert: false
                )
                // Don't abort — the clip is recorded locally. Enqueue it anyway so it's not lost.
            }
        } catch {
            // Network failure checking session status — proceed with upload anyway
            ErrorHandlerService.shared.handle(error, context: "CoachSessionManager.uploadClip.sessionCheck", showAlert: false)
        }

        let dateStr = Date().formatted(.iso8601.year().month().day())
        let fileName = "instruction_\(dateStr)_\(UUID().uuidString.prefix(8)).mov"

        // Move the video to a stable Documents path so it survives app backgrounding.
        // The queue will read from this path later.
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
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
            ErrorHandlerService.shared.handle(error, context: "CoachSessionManager.copyForQueue", showAlert: false)
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
