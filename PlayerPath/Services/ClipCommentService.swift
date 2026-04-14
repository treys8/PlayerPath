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
import os

private let commentLog = Logger(subsystem: "com.playerpath.app", category: "ClipComments")

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
    var category: String? = nil

    var isCoachComment: Bool { authorRole == "coach" }

    var annotationCategory: AnnotationCategory? {
        guard let category else { return nil }
        return AnnotationCategory(rawValue: category)
    }
}

// MARK: - Service

@MainActor
final class ClipCommentService {

    static let shared = ClipCommentService()
    private init() {}

    private let db = Firestore.firestore()

    /// In-memory cache keyed by clipId to avoid redundant Firestore fetches.
    private var cache: [String: [ClipComment]] = [:]

    /// Clears the cache for a specific clip (e.g. after posting a new comment).
    func invalidateCache(for clipId: String) {
        cache[clipId] = nil
    }

    // MARK: - Write

    /// Posts a comment to the clip's thread.
    /// Posts a comment and returns the new document ID so callers can link
    /// mirrored records (e.g. annotation → comment) for precise deletes.
    /// Returns nil when the text is empty (nothing written).
    @discardableResult
    func postComment(
        clipId: String,
        text: String,
        authorId: String,
        authorName: String,
        authorRole: String,
        category: String? = nil
    ) async throws -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Limit comment length to prevent abuse and excessive Firestore document size
        let clampedText = String(trimmed.prefix(2000))

        var data: [String: Any] = [
            "authorId": authorId,
            "authorName": authorName,
            "authorRole": authorRole,
            "text": clampedText,
            "createdAt": Timestamp(date: Date())
        ]
        if let category { data["category"] = category }

        let ref = try await db
            .collection(FC.videos)
            .document(clipId)
            .collection(FC.comments)
            .addDocument(data: data)

        // Invalidate cache so next fetch picks up the new comment
        invalidateCache(for: clipId)
        return ref.documentID
    }

    // MARK: - Read

    /// Fetches all comments for a clip, ordered by createdAt ascending.
    /// Returns cached results when available to avoid redundant Firestore reads.
    func fetchComments(clipId: String) async throws -> [ClipComment] {
        if let cached = cache[clipId] {
            return cached
        }

        let snapshot = try await db
            .collection(FC.videos)
            .document(clipId)
            .collection(FC.comments)
            .order(by: "createdAt")
            .limit(to: 100)
            .getDocuments()

        let comments = snapshot.documents.compactMap { doc -> ClipComment? in
            do {
                var comment = try doc.data(as: ClipComment.self)
                comment.id = doc.documentID
                return comment
            } catch {
                commentLog.warning("Failed to decode comment \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }

        cache[clipId] = comments
        return comments
    }

    // MARK: - Listen

    /// Attaches a Firestore snapshot listener for live updates. Returns the
    /// registration so the caller can detach on disappear. `onUpdate` is
    /// invoked on the main actor.
    func listenToComments(
        clipId: String,
        onUpdate: @escaping @MainActor ([ClipComment]) -> Void
    ) -> ListenerRegistration {
        return db
            .collection(FC.videos)
            .document(clipId)
            .collection(FC.comments)
            .order(by: "createdAt")
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    commentLog.warning("Comments listener error for \(clipId): \(error.localizedDescription)")
                    return
                }
                guard let snapshot else { return }
                let comments = snapshot.documents.compactMap { doc -> ClipComment? in
                    do {
                        var comment = try doc.data(as: ClipComment.self)
                        comment.id = doc.documentID
                        return comment
                    } catch {
                        commentLog.warning("Failed to decode comment \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                }
                Task { @MainActor in
                    self?.cache[clipId] = comments
                    onUpdate(comments)
                }
            }
    }
}
