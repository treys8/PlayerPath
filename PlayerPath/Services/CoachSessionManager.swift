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
    func createSession(
        coachID: String,
        coachName: String,
        athletes: [(athleteID: String, athleteName: String, folderID: String)]
    ) async throws -> String {
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
                var session = try? doc.data(as: CoachSession.self)
                session?.id = doc.documentID
                return session
            }

            // Detect if there's an active (live/reviewing) session
            activeSession = sessions.first(where: { $0.status.isActive })
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

            async let uploadTask = VideoCloudManager.shared.uploadVideo(
                localURL: videoURL,
                fileName: fileName,
                folderID: folderID,
                progressHandler: { _ in }
            )
            async let processTask = CoachVideoProcessingService.shared.process(
                videoURL: videoURL,
                fileName: fileName,
                folderID: folderID
            )

            let (storageURL, processed) = try await (uploadTask, processTask)

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

            try? FileManager.default.removeItem(at: videoURL)

            await incrementClipCount(sessionID: sessionID)
        } catch {
            ErrorHandlerService.shared.handle(error, context: "CoachSessionManager.uploadClip", showAlert: false)
        }
    }
}
