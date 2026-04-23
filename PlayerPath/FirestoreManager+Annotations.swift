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
        drawingCanvasHeight: Double? = nil,
        shapes: String? = nil
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
        if let shapes { annotationData["shapes"] = shapes }

        do {
            // Batch the annotation insert and the video-doc counter increment
            // so they land atomically. Previously the increment was a
            // best-effort follow-up call; if it failed, annotationCount drifted
            // permanently behind the real count.
            let annotationRef = db.collection(FC.videos)
                .document(videoID)
                .collection(FC.annotations)
                .document()
            let videoRef = db.collection(FC.videos).document(videoID)

            let batch = db.batch()
            batch.setData(annotationData, forDocument: annotationRef)
            // Bump the lumped annotationCount and, for drawings, the split
            // drawingCount so thumbnails can render a pencil badge separate
            // from the comment-bubble badge.
            var videoUpdates: [String: Any] = [
                "annotationCount": FieldValue.increment(Int64(1))
            ]
            if type == "drawing" {
                videoUpdates["drawingCount"] = FieldValue.increment(Int64(1))
            }
            batch.updateData(videoUpdates, forDocument: videoRef)
            try await batch.commit()

            return annotationRef.documentID
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

    /// Stores the ID of the mirrored comment document on the annotation,
    /// enabling precise deletion of the paired comment later.
    func setAnnotationMirrorCommentID(
        videoID: String,
        annotationID: String,
        mirrorCommentID: String
    ) async {
        do {
            try await db.collection(FC.videos)
                .document(videoID)
                .collection(FC.annotations)
                .document(annotationID)
                .updateData(["mirrorCommentID": mirrorCommentID])
        } catch {
            firestoreLog.warning("Failed to set mirrorCommentID on annotation \(annotationID): \(error.localizedDescription)")
        }
    }

    /// Attaches a Firestore snapshot listener for live annotation updates.
    /// Returns the registration so callers can detach on deinit/disappear.
    func listenToAnnotations(
        forVideo videoID: String,
        onUpdate: @escaping @MainActor ([VideoAnnotation]) -> Void
    ) -> ListenerRegistration {
        return db.collection(FC.videos)
            .document(videoID)
            .collection(FC.annotations)
            .order(by: "timestamp")
            .limit(to: 50)
            .addSnapshotListener { snapshot, error in
                if let error {
                    // Permission errors are expected for private videos — stay silent.
                    let ns = error as NSError
                    if !(ns.domain == "FIRFirestoreErrorDomain" && ns.code == 7) {
                        firestoreLog.warning("Annotations listener error for \(videoID): \(error.localizedDescription)")
                    }
                    return
                }
                guard let snapshot else { return }
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
                Task { @MainActor in
                    onUpdate(annotations)
                }
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

            // Best-effort: delete the mirrored comment in comments/ subcollection.
            // Prefer the explicit mirrorCommentID written at creation time. Fall
            // back to a userID+text query for legacy annotations missing the ID
            // — accepting the known ambiguity for duplicate-text cases rather
            // than stranding old mirrors.
            if let mirrorCommentID = annotationData?["mirrorCommentID"] as? String,
               !mirrorCommentID.isEmpty {
                do {
                    try await db.collection(FC.videos)
                        .document(videoID)
                        .collection("comments")
                        .document(mirrorCommentID)
                        .delete()
                } catch {
                    firestoreLog.warning("Failed to delete mirrored comment \(mirrorCommentID) for annotation \(annotationID): \(error.localizedDescription)")
                }
            } else if let userID = annotationData?["userID"] as? String,
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

            // Decrement annotationCount — and drawingCount if the deleted
            // annotation was a drawing — floored at 0 in a single transaction.
            let wasDrawing = (annotationData?["type"] as? String) == "drawing"
            let videoRef = db.collection(FC.videos).document(videoID)
            do {
                _ = try await db.runTransaction { transaction, errorPointer in
                    do {
                        let doc = try transaction.getDocument(videoRef)
                        let currentAC = doc.data()?["annotationCount"] as? Int64 ?? 0
                        var updates: [String: Any] = [
                            "annotationCount": max(Int64(0), currentAC - 1)
                        ]
                        if wasDrawing {
                            let currentDC = doc.data()?["drawingCount"] as? Int64 ?? 0
                            updates["drawingCount"] = max(Int64(0), currentDC - 1)
                        }
                        transaction.updateData(updates, forDocument: videoRef)
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
        drawingCanvasHeight: Double? = nil,
        shapes: String? = nil
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
            drawingCanvasHeight: drawingCanvasHeight,
            shapes: shapes
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
            drawingCanvasHeight: drawingCanvasHeight,
            shapes: shapes
        )
    }
}
