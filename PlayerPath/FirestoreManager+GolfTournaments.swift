//
//  FirestoreManager+GolfTournaments.swift
//  PlayerPath
//
//  Multi-round golf tournament CRUD (SchemaV27). Mirrors the season CRUD in
//  FirestoreManager+EntitySync — a per-athlete top-level subcollection at
//  `users/{uid}/golfTournaments/{id}`. Kept in its own file so +EntitySync
//  doesn't keep growing.
//

import Foundation
import FirebaseFirestore
import os

extension FirestoreManager {

    /// Creates a new golf tournament in Firestore for cross-device sync.
    /// - Returns: The Firestore document ID for the created tournament.
    func createGolfTournament(userId: String, data: [String: Any]) async throws -> String {
        var tournamentData = data
        tournamentData["createdAt"] = FieldValue.serverTimestamp()
        tournamentData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            let docRef = try await db
                .collection(FC.users)
                .document(userId)
                .collection(FC.golfTournaments)
                .addDocument(data: tournamentData)
            return docRef.documentID
        } catch {
            firestoreLog.error("Failed to create golf tournament: \(error.localizedDescription)")
            errorMessage = "Failed to create tournament."
            throw error
        }
    }

    /// Updates an existing golf tournament in Firestore.
    func updateGolfTournament(userId: String, tournamentId: String, data: [String: Any]) async throws {
        let allowedFields: Set<String> = [
            "id", "name", "athleteId", "location", "startDate", "endDate", "notes", "version"
        ]
        var updateData = data.filter { allowedFields.contains($0.key) }
        updateData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            try await db
                .collection(FC.users)
                .document(userId)
                .collection(FC.golfTournaments)
                .document(tournamentId)
                .setData(updateData, merge: true)
        } catch {
            firestoreLog.error("Failed to update golf tournament: \(error.localizedDescription)")
            errorMessage = "Failed to update tournament."
            throw error
        }
    }

    /// Fetches all (non-deleted) golf tournaments for a user, paginated.
    func fetchGolfTournaments(userId: String) async throws -> [FirestoreGolfTournament] {
        do {
            var tournaments: [FirestoreGolfTournament] = []
            var lastDoc: QueryDocumentSnapshot?
            var totalSeen = 0
            let baseQuery = db
                .collection(FC.users)
                .document(userId)
                .collection(FC.golfTournaments)
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "createdAt", descending: true)

            while true {
                var query = baseQuery.limit(to: 100)
                if let lastDoc { query = query.start(afterDocument: lastDoc) }
                let snapshot = try await query.getDocuments()
                guard !snapshot.documents.isEmpty else { break }
                lastDoc = snapshot.documents.last
                totalSeen += snapshot.documents.count
                tournaments.append(contentsOf: snapshot.documents.compactMap { doc -> FirestoreGolfTournament? in
                    do {
                        var tournament = try doc.data(as: FirestoreGolfTournament.self)
                        tournament.id = doc.documentID
                        return tournament
                    } catch {
                        firestoreLog.warning("Failed to decode FirestoreGolfTournament from doc \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                })
                if snapshot.documents.count < 100 { break }
            }

            if tournaments.count < totalSeen {
                firestoreLog.error("Partial decode in fetchGolfTournaments: \(tournaments.count)/\(totalSeen) — skipping to avoid sync deletion")
                throw FirestoreSyncError.partialDecode(entity: "GolfTournament", decoded: tournaments.count, total: totalSeen)
            }
            return tournaments
        } catch {
            firestoreLog.error("Failed to fetch golf tournaments: \(error.localizedDescription)")
            errorMessage = "Failed to fetch tournaments."
            throw error
        }
    }

    /// Soft deletes a golf tournament in Firestore. Rounds keep their own docs —
    /// the client clears each round's `tournamentId` separately on the next game
    /// sync (see GolfTournament.delete(in:)).
    func deleteGolfTournament(userId: String, tournamentId: String) async throws {
        do {
            try await db
                .collection(FC.users)
                .document(userId)
                .collection(FC.golfTournaments)
                .document(tournamentId)
                .updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])
        } catch {
            firestoreLog.error("Failed to delete golf tournament: \(error.localizedDescription)")
            errorMessage = "Failed to delete tournament."
            throw error
        }
    }
}
