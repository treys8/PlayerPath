//
//  FirestoreManager+Shots.swift
//  PlayerPath
//
//  CRUD for per-shot golf rows (SchemaV30). Nested subcollection under the hole
//  doc: `users/{uid}/games|practices/{parentId}/holes/{N}/shots/{shotId}`.
//
//  Unlike hole scores (doc id = hole number), the shot doc id is the shot UUID
//  string. Shots reorder on delete/insert, so a positional id would overwrite
//  on renumber; `shotNumber` is a plain sort field instead.
//

import Foundation
import FirebaseFirestore
import os

extension FirestoreManager {

    // Fields the update path is allowed to write. `shotNumber` is included so a
    // reorder (delete/insert) replicates; the optional fields below are deleted
    // remotely when cleared locally.
    private static let shotAllowedFields: Set<String> = [
        "id", "shotNumber", "club", "lie", "outcome",
        "penaltyStrokes", "distanceBefore", "isPutt", "version"
    ]

    private func shotUpdatePayload(from data: [String: Any]) -> [String: Any] {
        var updateData = data.filter { FirestoreManager.shotAllowedFields.contains($0.key) }
        // Only the *optional* fields are deleted when absent. penaltyStrokes /
        // isPutt are defaulted non-optionals always present in toFirestoreData,
        // so they must NOT be in this loop (would clear a legitimate 0/false).
        for field in ["club", "distanceBefore"] where updateData[field] == nil {
            updateData[field] = FieldValue.delete()
        }
        updateData["updatedAt"] = FieldValue.serverTimestamp()
        return updateData
    }

    // MARK: - Game shots

    func createGameShot(userId: String, gameFirestoreId: String, holeNumber: Int, shotId: String, data: [String: Any]) async throws {
        var shotData = data
        shotData["createdAt"] = FieldValue.serverTimestamp()
        shotData["updatedAt"] = FieldValue.serverTimestamp()
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.games).document(gameFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .collection(FC.shots).document(shotId)
            .setData(shotData, merge: true)
    }

    func updateGameShot(userId: String, gameFirestoreId: String, holeNumber: Int, shotId: String, data: [String: Any]) async throws {
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.games).document(gameFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .collection(FC.shots).document(shotId)
            .setData(shotUpdatePayload(from: data), merge: true)
    }

    func deleteGameShot(userId: String, gameFirestoreId: String, holeNumber: Int, shotId: String) async throws {
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.games).document(gameFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .collection(FC.shots).document(shotId)
            .updateData([
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }

    func fetchGameShots(userId: String, gameFirestoreId: String, holeNumber: Int) async throws -> [FirestoreShot] {
        let snapshot = try await db
            .collection(FC.users).document(userId)
            .collection(FC.games).document(gameFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .collection(FC.shots)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()
        return decodeShots(snapshot)
    }

    // MARK: - Practice shots

    func createPracticeShot(userId: String, practiceFirestoreId: String, holeNumber: Int, shotId: String, data: [String: Any]) async throws {
        var shotData = data
        shotData["createdAt"] = FieldValue.serverTimestamp()
        shotData["updatedAt"] = FieldValue.serverTimestamp()
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.practices).document(practiceFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .collection(FC.shots).document(shotId)
            .setData(shotData, merge: true)
    }

    func updatePracticeShot(userId: String, practiceFirestoreId: String, holeNumber: Int, shotId: String, data: [String: Any]) async throws {
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.practices).document(practiceFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .collection(FC.shots).document(shotId)
            .setData(shotUpdatePayload(from: data), merge: true)
    }

    func deletePracticeShot(userId: String, practiceFirestoreId: String, holeNumber: Int, shotId: String) async throws {
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.practices).document(practiceFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .collection(FC.shots).document(shotId)
            .updateData([
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }

    func fetchPracticeShots(userId: String, practiceFirestoreId: String, holeNumber: Int) async throws -> [FirestoreShot] {
        let snapshot = try await db
            .collection(FC.users).document(userId)
            .collection(FC.practices).document(practiceFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .collection(FC.shots)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()
        return decodeShots(snapshot)
    }

    private func decodeShots(_ snapshot: QuerySnapshot) -> [FirestoreShot] {
        snapshot.documents.compactMap { doc -> FirestoreShot? in
            do {
                var shot = try doc.data(as: FirestoreShot.self)
                shot.id = doc.documentID
                return shot
            } catch {
                firestoreLog.warning("Failed to decode FirestoreShot from \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }
}
