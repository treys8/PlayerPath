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

// @MainActor ensures the comment cache dictionary is never accessed
// from multiple threads — Firestore snapshot listeners run on background
// threads but @MainActor serializes all property access.

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

@MainActor
final class ClipCommentService {

    static let shared = ClipCommentService()
    private init() {}

    private let db = Firestore.firestore()

    /// In-memory cache keyed by clipId to avoid redundant Firestore fetches.
    private var cache: [String: [ClipComment]] = [:]

    /// Returns cached comments for a clip, or nil if not yet fetched.
    func cachedComments(for clipId: String) -> [ClipComment]? {
        cache[clipId]
    }

    /// Clears the cache for a specific clip (e.g. after posting a new comment).
    func invalidateCache(for clipId: String) {
        cache[clipId] = nil
    }

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

        // Invalidate cache so next fetch picks up the new comment
        invalidateCache(for: clipId)
    }

    // MARK: - Read

    /// Fetches all comments for a clip, ordered by createdAt ascending.
    /// Returns cached results when available to avoid redundant Firestore reads.
    func fetchComments(clipId: String) async throws -> [ClipComment] {
        if let cached = cache[clipId] {
            return cached
        }

        let snapshot = try await db
            .collection("videos")
            .document(clipId)
            .collection("comments")
            .order(by: "createdAt")
            .limit(to: 100)
            .getDocuments()

        let comments = snapshot.documents.compactMap { doc -> ClipComment? in
            var comment = try? doc.data(as: ClipComment.self)
            comment?.id = doc.documentID
            return comment
        }

        cache[clipId] = comments
        return comments
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
            .limit(to: 100)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    if error != nil {
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
