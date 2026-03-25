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
    var isLoading = false

    private let db = Firestore.firestore()
    private init() {}

    // MARK: - Session Lifecycle

    /// Creates a new live session and returns its ID.
    /// Validates that the selected athletes don't exceed the coach's tier limit.
    func createSession(
        coachID: String,
        coachName: String,
        athletes: [(athleteID: String, athleteName: String, folderID: String)],
        authManager: ComprehensiveAuthManager
    ) async throws -> String {
        // Enforce coach athlete limit before creating the session
        let limit = authManager.coachAthleteLimit
        if limit != Int.max {
            let connectedCount = await SubscriptionGate.fullConnectedAthleteCount(coachID: coachID)
            if connectedCount > limit {
                throw CoachSessionError.athleteLimitExceeded(limit: limit)
            }
        }

        let athleteIDs = athletes.map(\.athleteID)
        let athleteNames = Dictionary(uniqueKeysWithValues: athletes.map { ($0.athleteID, $0.athleteName) })
        let folderIDs = Dictionary(uniqueKeysWithValues: athletes.map { ($0.athleteID, $0.folderID) })

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
            let snapshot = try await db.collection(FC.coachSessions)
                .whereField("coachID", isEqualTo: coachID)
                .order(by: "startedAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            sessions = snapshot.documents.compactMap { doc in
                do {
                    var session = try doc.data(as: CoachSession.self)
                    session.id = doc.documentID
                    return session
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "CoachSessionManager.decode(\(doc.documentID))", showAlert: false)
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

    /// Uploads a recorded clip to Firebase Storage and writes metadata to Firestore.
    /// Retries the Storage upload up to 3 times for transient network failures.
    /// Increments clip count automatically after successful upload.
    func uploadClip(
        videoURL: URL,
        folderID: String,
        sessionID: String,
        coachID: String,
        coachName: String
    ) async {
        let dateStr = Date().formatted(.iso8601.year().month().day())
        let fileName = "instruction_\(dateStr)_\(UUID().uuidString.prefix(8)).mov"

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            // Run Storage upload (with retry) and thumbnail processing in parallel
            async let uploadTask: String = withRetry(maxAttempts: 3, delay: .seconds(3)) {
                try await VideoCloudManager.shared.uploadVideo(
                    localURL: videoURL,
                    fileName: fileName,
                    folderID: folderID,
                    progressHandler: { _ in }
                )
            }
            async let processTask = processWithThumbnailRetry(
                videoURL: videoURL, fileName: fileName, folderID: folderID
            )

            let (storageURL, processed) = try await (uploadTask, processTask)

            // Metadata write — rollback Storage upload on failure
            do {
                _ = try await FirestoreManager.shared.uploadVideoMetadata(
                    fileName: fileName,
                    storageURL: storageURL,
                    thumbnail: processed.thumbnailURL.map { ThumbnailMetadata(standardURL: $0) },
                    folderID: folderID,
                    uploadedBy: coachID,
                    uploadedByName: coachName,
                    fileSize: fileSize,
                    duration: processed.duration,
                    videoType: "instruction",
                    practiceContext: PracticeContext(date: Date()),
                    uploadedByType: .coach,
                    visibility: "private",
                    sessionID: sessionID
                )
            } catch {
                ErrorHandlerService.shared.handle(error, context: "CoachSession.metadataRollback", showAlert: false)
                try? await VideoCloudManager.shared.deleteVideo(fileName: fileName, folderID: folderID)
                try? await VideoCloudManager.shared.deleteThumbnail(videoFileName: fileName, folderID: folderID)
                throw error
            }

            // Only delete local file after full success
            try? FileManager.default.removeItem(at: videoURL)

            await incrementClipCount(sessionID: sessionID)
        } catch {
            ErrorHandlerService.shared.handle(error, context: "CoachSessionManager.uploadClip", showAlert: false)
        }
    }

    /// Processes video with a single thumbnail retry if the first attempt fails.
    private func processWithThumbnailRetry(
        videoURL: URL, fileName: String, folderID: String
    ) async -> CoachVideoProcessingService.ProcessedVideo {
        let result = await CoachVideoProcessingService.shared.process(
            videoURL: videoURL, fileName: fileName, folderID: folderID
        )
        if result.thumbnailURL == nil {
            try? await Task.sleep(for: .seconds(2))
            return await CoachVideoProcessingService.shared.process(
                videoURL: videoURL, fileName: fileName, folderID: folderID
            )
        }
        return result
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
