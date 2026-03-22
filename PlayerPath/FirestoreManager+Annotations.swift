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
        templateID: String? = nil
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
                .limit(to: 200)
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

            return annotations
        } catch {
            throw error
        }
    }

    /// Real-time listener for annotations (for live updates)
    func listenToAnnotations(
        videoID: String,
        completion: @escaping ([VideoAnnotation]) -> Void
    ) -> ListenerRegistration {
        return db.collection(FC.videos)
            .document(videoID)
            .collection(FC.annotations)
            .order(by: "timestamp")
            .limit(to: 200)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    return
                }

                let annotations = documents.compactMap { doc -> VideoAnnotation? in
                    do {
                        var annotation = try doc.data(as: VideoAnnotation.self)
                        annotation.id = doc.documentID
                        return annotation
                    } catch {
                        firestoreLog.warning("Failed to decode VideoAnnotation from doc \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                }

                completion(annotations)
            }
    }

    /// Deletes an annotation (user can only delete their own)
    func deleteAnnotation(videoID: String, annotationID: String) async throws {
        do {
            try await db.collection(FC.videos)
                .document(videoID)
                .collection(FC.annotations)
                .document(annotationID)
                .delete()

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
        templateID: String? = nil
    ) async throws -> VideoAnnotation {
        let annotationID = try await addAnnotation(
            videoID: videoID,
            userID: userID,
            userName: userName,
            timestamp: timestamp,
            text: text,
            isCoachComment: isCoachComment,
            category: category,
            templateID: templateID
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
            templateID: templateID
        )
    }
}
