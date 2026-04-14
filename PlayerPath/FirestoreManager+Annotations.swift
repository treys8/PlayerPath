//
//  FirestoreManager+Annotations.swift
//  PlayerPath
//
//  Annotation operations for FirestoreManager
//

import Foundation
import FirebaseFirestore
import os

extension FirestoreManager {

    // MARK: - Annotations

    /// Adds a comment/annotation to a video
    func addAnnotation(
        videoID: String,
        userID: String,
        userName: String,
        timestamp: Double,
        text: String,
        isCoachComment: Bool,
        category: String? = nil,
        templateID: String? = nil,
        type: String? = nil,
        drawingData: String? = nil,
        drawingCanvasWidth: Double? = nil,
        drawingCanvasHeight: Double? = nil
    ) async throws -> String {
        var annotationData: [String: Any] = [
            "userID": userID,
            "userName": userName,
            "timestamp": timestamp,
            "text": text,
            "createdAt": FieldValue.serverTimestamp(),
            "isCoachComment": isCoachComment
        ]
        if let category { annotationData["category"] = category }
        if let templateID { annotationData["templateID"] = templateID }
        if let type { annotationData["type"] = type }
        if let drawingData { annotationData["drawingData"] = drawingData }
        if let drawingCanvasWidth { annotationData["drawingCanvasWidth"] = drawingCanvasWidth }
        if let drawingCanvasHeight { annotationData["drawingCanvasHeight"] = drawingCanvasHeight }

        do {
            let docRef = try await db.collection(FC.videos)
                .document(videoID)
                .collection(FC.annotations)
                .addDocument(data: annotationData)

            // Increment annotationCount on the video document
            do {
                try await db.collection(FC.videos).document(videoID)
                    .updateData(["annotationCount": FieldValue.increment(Int64(1))])
            } catch {
                firestoreLog.warning("Failed to increment annotationCount for video \(videoID): \(error.localizedDescription)")
            }

            return docRef.documentID
        } catch {
            firestoreLog.error("Failed to add comment: \(error.localizedDescription)")
            errorMessage = "Failed to add comment."
            throw error
        }
    }

    /// Fetches all annotations for a video
    func fetchAnnotations(forVideo videoID: String) async throws -> [VideoAnnotation] {
        do {
            let snapshot = try await db.collection(FC.videos)
                .document(videoID)
                .collection(FC.annotations)
                .order(by: "timestamp")
                .limit(to: 50)
                .getDocuments()

            let annotations = snapshot.documents.compactMap { doc -> VideoAnnotation? in
                do {
                    var annotation = try doc.data(as: VideoAnnotation.self)
                    annotation.id = doc.documentID
                    return annotation
                } catch {
                    firestoreLog.warning("Failed to decode VideoAnnotation from doc \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }

            if annotations.count >= 50 {
                firestoreLog.warning("Annotations for video \(videoID) hit 50 limit — some may be missing")
            }

            return annotations
        } catch {
            firestoreLog.error("Failed to fetch annotations for video: \(error.localizedDescription)")
            throw error
        }
    }

    /// Deletes an annotation and its mirrored comment (user can only delete their own)
    func deleteAnnotation(videoID: String, annotationID: String) async throws {
        do {
            // Read the annotation before deleting so we can find its mirrored comment
            let annotationDoc = try await db.collection(FC.videos)
                .document(videoID)
                .collection(FC.annotations)
                .document(annotationID)
                .getDocument()
            let annotationData = annotationDoc.data()

            // Delete the annotation
            try await db.collection(FC.videos)
                .document(videoID)
                .collection(FC.annotations)
                .document(annotationID)
                .delete()

            // Best-effort: delete the mirrored comment in comments/ subcollection
            if let userID = annotationData?["userID"] as? String,
               let text = annotationData?["text"] as? String {
                do {
                    let commentsQuery = db.collection(FC.videos)
                        .document(videoID)
                        .collection("comments")
                        .whereField("authorId", isEqualTo: userID)
                        .whereField("text", isEqualTo: text)
                        .limit(to: 1)
                    let commentsSnap = try await commentsQuery.getDocuments()
                    for doc in commentsSnap.documents {
                        try await doc.reference.delete()
                    }
                } catch {
                    firestoreLog.warning("Failed to delete mirrored comment for annotation \(annotationID): \(error.localizedDescription)")
                }
            }

            // Decrement annotationCount, floored at 0 via transaction
            let videoRef = db.collection(FC.videos).document(videoID)
            do {
                _ = try await db.runTransaction { transaction, errorPointer in
                    do {
                        let doc = try transaction.getDocument(videoRef)
                        let current = doc.data()?["annotationCount"] as? Int64 ?? 0
                        transaction.updateData(["annotationCount": max(Int64(0), current - 1)], forDocument: videoRef)
                    } catch let fetchError as NSError {
                        errorPointer?.pointee = fetchError
                    }
                    return nil
                }
            } catch {
                firestoreLog.warning("Failed to decrement annotationCount for video \(videoID): \(error.localizedDescription)")
            }

        } catch {
            firestoreLog.error("Failed to delete comment: \(error.localizedDescription)")
            errorMessage = "Failed to delete comment."
            throw error
        }
    }

    /// Creates an annotation (convenience method)
    func createAnnotation(
        videoID: String,
        text: String,
        timestamp: Double,
        userID: String,
        userName: String,
        isCoachComment: Bool,
        category: String? = nil,
        templateID: String? = nil,
        type: String? = nil,
        drawingData: String? = nil,
        drawingCanvasWidth: Double? = nil,
        drawingCanvasHeight: Double? = nil
    ) async throws -> VideoAnnotation {
        let annotationID = try await addAnnotation(
            videoID: videoID,
            userID: userID,
            userName: userName,
            timestamp: timestamp,
            text: text,
            isCoachComment: isCoachComment,
            category: category,
            templateID: templateID,
            type: type,
            drawingData: drawingData,
            drawingCanvasWidth: drawingCanvasWidth,
            drawingCanvasHeight: drawingCanvasHeight
        )

        return VideoAnnotation(
            id: annotationID,
            userID: userID,
            userName: userName,
            timestamp: timestamp,
            text: text,
            createdAt: Date(),
            isCoachComment: isCoachComment,
            category: category,
            templateID: templateID,
            type: type,
            drawingData: drawingData,
            drawingCanvasWidth: drawingCanvasWidth,
            drawingCanvasHeight: drawingCanvasHeight
        )
    }
}
