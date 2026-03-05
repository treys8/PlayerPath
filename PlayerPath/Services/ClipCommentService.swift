//
//  ClipCommentService.swift
//  PlayerPath
//
//  Unified comment thread for VideoClip.
//  Firestore path: videos/{clipId}/comments/{commentId}
//
//  Both athletes and coaches write to this subcollection.
//  authorRole distinguishes who wrote each comment ("athlete" | "coach").
//  Designed to support two-way threads; v1 ships one-way (coach replies, athlete reads).
//

import Foundation
import FirebaseFirestore

// MARK: - Model

struct ClipComment: Codable, Identifiable {
    var id: String?
    let authorId: String
    let authorName: String
    let authorRole: String   // "athlete" | "coach"
    let text: String
    let createdAt: Date?

    var isCoachComment: Bool { authorRole == "coach" }
}

// MARK: - Service

final class ClipCommentService {

    static let shared = ClipCommentService()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: - Write

    /// Posts a comment to the clip's thread.
    func postComment(
        clipId: String,
        text: String,
        authorId: String,
        authorName: String,
        authorRole: String
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let data: [String: Any] = [
            "authorId": authorId,
            "authorName": authorName,
            "authorRole": authorRole,
            "text": trimmed,
            "createdAt": Timestamp(date: Date())
        ]

        try await db
            .collection("videos")
            .document(clipId)
            .collection("comments")
            .addDocument(data: data)
    }

    // MARK: - Read

    /// Fetches all comments for a clip, ordered by createdAt ascending.
    func fetchComments(clipId: String) async throws -> [ClipComment] {
        let snapshot = try await db
            .collection("videos")
            .document(clipId)
            .collection("comments")
            .order(by: "createdAt")
            .getDocuments()

        return snapshot.documents.compactMap { doc -> ClipComment? in
            var comment = try? doc.data(as: ClipComment.self)
            comment?.id = doc.documentID
            return comment
        }
    }

    // MARK: - Real-time listener

    /// Attaches a real-time listener for a clip's comment thread.
    /// Caller is responsible for removing the returned `ListenerRegistration` on deinit.
    @discardableResult
    func listenForComments(
        clipId: String,
        onUpdate: @escaping ([ClipComment]) -> Void
    ) -> ListenerRegistration {
        return db
            .collection("videos")
            .document(clipId)
            .collection("comments")
            .order(by: "createdAt")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    if let error = error {
                        print("❌ ClipCommentService listener error: \(error.localizedDescription)")
                    }
                    return
                }
                let comments = documents.compactMap { doc -> ClipComment? in
                    var comment = try? doc.data(as: ClipComment.self)
                    comment?.id = doc.documentID
                    return comment
                }
                onUpdate(comments)
            }
    }
}
