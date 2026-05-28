//
//  FirestoreManager+HighlightReels.swift
//  PlayerPath
//
//  CRUD for virtual highlight reels (SchemaV25 / v6.1 PR2). Top-level athlete
//  collection at `users/{uid}/highlightReels/{reelId}` where the doc id is
//  the reel's UUID string — different from HoleScore which keys on hole
//  number under the parent game. Reels are owner-only; no coach access in v1.
//

import Foundation
import FirebaseFirestore
import os

extension FirestoreManager {

    func createHighlightReel(userId: String, reelId: String, data: [String: Any]) async throws {
        var reelData = data
        reelData["createdAt"] = FieldValue.serverTimestamp()
        reelData["updatedAt"] = FieldValue.serverTimestamp()
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.highlightReels).document(reelId)
            .setData(reelData, merge: true)
    }

    func updateHighlightReel(userId: String, reelId: String, data: [String: Any]) async throws {
        let allowedFields: Set<String> = [
            "id", "athleteID", "gameID", "practiceID",
            "holeNumber", "score", "par", "displayName", "courseOrOpponent",
            "clipIDs", "date", "version", "isDeleted"
        ]
        var updateData = data.filter { allowedFields.contains($0.key) }
        updateData["updatedAt"] = FieldValue.serverTimestamp()
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.highlightReels).document(reelId)
            .setData(updateData, merge: true)
    }

    func deleteHighlightReel(userId: String, reelId: String) async throws {
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.highlightReels).document(reelId)
            .updateData([
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }

    func fetchHighlightReels(userId: String, athleteId: String) async throws -> [FirestoreHighlightReel] {
        let snapshot = try await db
            .collection(FC.users).document(userId)
            .collection(FC.highlightReels)
            .whereField("athleteID", isEqualTo: athleteId)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()
        return snapshot.documents.compactMap { doc -> FirestoreHighlightReel? in
            do {
                var reel = try doc.data(as: FirestoreHighlightReel.self)
                reel.id = doc.documentID
                return reel
            } catch {
                firestoreLog.warning("Failed to decode FirestoreHighlightReel from \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }
}
