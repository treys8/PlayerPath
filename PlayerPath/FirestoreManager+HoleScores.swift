//
//  FirestoreManager+HoleScores.swift
//  PlayerPath
//
//  CRUD for per-hole golf scoring rows (SchemaV25). Subcollection under both
//  games and practices — practice paths are wired up but only used by PR3.
//  Doc id is the hole number string ("1"…"18"), giving us natural upsert
//  semantics: a second write for the same hole overwrites the first.
//

import Foundation
import FirebaseFirestore
import os

extension FirestoreManager {

    // MARK: - Game hole scores

    func createGameHoleScore(userId: String, gameFirestoreId: String, holeNumber: Int, data: [String: Any]) async throws {
        var holeData = data
        holeData["createdAt"] = FieldValue.serverTimestamp()
        holeData["updatedAt"] = FieldValue.serverTimestamp()
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.games).document(gameFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .setData(holeData, merge: true)
    }

    func updateGameHoleScore(userId: String, gameFirestoreId: String, holeNumber: Int, data: [String: Any]) async throws {
        let allowedFields: Set<String> = ["id", "holeNumber", "par", "score", "putts", "version"]
        var updateData = data.filter { allowedFields.contains($0.key) }
        updateData["updatedAt"] = FieldValue.serverTimestamp()
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.games).document(gameFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .setData(updateData, merge: true)
    }

    func deleteGameHoleScore(userId: String, gameFirestoreId: String, holeNumber: Int) async throws {
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.games).document(gameFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .updateData([
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }

    func fetchGameHoleScores(userId: String, gameFirestoreId: String) async throws -> [FirestoreHoleScore] {
        let snapshot = try await db
            .collection(FC.users).document(userId)
            .collection(FC.games).document(gameFirestoreId)
            .collection(FC.holes)
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 18)
            .getDocuments()
        return snapshot.documents.compactMap { doc -> FirestoreHoleScore? in
            do {
                var hole = try doc.data(as: FirestoreHoleScore.self)
                hole.id = doc.documentID
                return hole
            } catch {
                firestoreLog.warning("Failed to decode FirestoreHoleScore from \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: - Practice hole scores (wired up for PR3)

    func createPracticeHoleScore(userId: String, practiceFirestoreId: String, holeNumber: Int, data: [String: Any]) async throws {
        var holeData = data
        holeData["createdAt"] = FieldValue.serverTimestamp()
        holeData["updatedAt"] = FieldValue.serverTimestamp()
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.practices).document(practiceFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .setData(holeData, merge: true)
    }

    func updatePracticeHoleScore(userId: String, practiceFirestoreId: String, holeNumber: Int, data: [String: Any]) async throws {
        let allowedFields: Set<String> = ["id", "holeNumber", "par", "score", "putts", "version"]
        var updateData = data.filter { allowedFields.contains($0.key) }
        updateData["updatedAt"] = FieldValue.serverTimestamp()
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.practices).document(practiceFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .setData(updateData, merge: true)
    }

    func deletePracticeHoleScore(userId: String, practiceFirestoreId: String, holeNumber: Int) async throws {
        try await db
            .collection(FC.users).document(userId)
            .collection(FC.practices).document(practiceFirestoreId)
            .collection(FC.holes).document(String(holeNumber))
            .updateData([
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }

    func fetchPracticeHoleScores(userId: String, practiceFirestoreId: String) async throws -> [FirestoreHoleScore] {
        let snapshot = try await db
            .collection(FC.users).document(userId)
            .collection(FC.practices).document(practiceFirestoreId)
            .collection(FC.holes)
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 18)
            .getDocuments()
        return snapshot.documents.compactMap { doc -> FirestoreHoleScore? in
            do {
                var hole = try doc.data(as: FirestoreHoleScore.self)
                hole.id = doc.documentID
                return hole
            } catch {
                firestoreLog.warning("Failed to decode FirestoreHoleScore from \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }
}
