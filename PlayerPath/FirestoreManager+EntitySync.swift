//
//  FirestoreManager+EntitySync.swift
//  PlayerPath
//
//  Entity sync operations for FirestoreManager
//

import Foundation
import FirebaseFirestore
import os

extension FirestoreManager {

    // MARK: - Athletes Sync

    /// Creates a new athlete in Firestore for cross-device sync
    /// - Parameters:
    ///   - userId: The user ID who owns this athlete
    ///   - data: Athlete data dictionary (from Athlete.toFirestoreData())
    /// - Returns: The Firestore document ID for the created athlete
    func createAthlete(userId: String, data: [String: Any]) async throws -> String {

        var athleteData = data
        athleteData["createdAt"] = FieldValue.serverTimestamp()
        athleteData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            let docRef = try await db
                .collection("users")
                .document(userId)
                .collection("athletes")
                .addDocument(data: athleteData)

            return docRef.documentID
        } catch {
            errorMessage = "Failed to create athlete."
            throw error
        }
    }

    /// Updates an existing athlete in Firestore
    /// - Parameters:
    ///   - userId: The user ID who owns this athlete
    ///   - athleteId: The Firestore document ID of the athlete
    ///   - data: Updated athlete data dictionary
    func updateAthlete(userId: String, athleteId: String, data: [String: Any]) async throws {

        var updateData = data
        updateData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("athletes")
                .document(athleteId)
                .setData(updateData, merge: true)

        } catch {
            errorMessage = "Failed to update athlete."
            throw error
        }
    }

    /// Fetches all athletes for a user from Firestore
    /// - Parameter userId: The user ID to fetch athletes for
    /// - Returns: Array of FirestoreAthlete objects
    func fetchAthletes(userId: String) async throws -> [FirestoreAthlete] {

        do {
            let snapshot = try await db
                .collection("users")
                .document(userId)
                .collection("athletes")
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "createdAt", descending: false)
                .limit(to: 100)
                .getDocuments()

            let athletes = snapshot.documents.compactMap { doc -> FirestoreAthlete? in
                do {
                    var athlete = try doc.data(as: FirestoreAthlete.self)
                    athlete.id = doc.documentID
                    return athlete
                } catch {
                    firestoreLog.warning("Failed to decode FirestoreAthlete from doc \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }

            return athletes
        } catch {
            errorMessage = "Failed to load athletes."
            throw error
        }
    }

    /// Soft deletes an athlete in Firestore (marks as deleted, doesn't remove)
    /// - Parameters:
    ///   - userId: The user ID who owns this athlete
    ///   - athleteId: The Firestore document ID of the athlete
    func deleteAthlete(userId: String, athleteId: String) async throws {

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("athletes")
                .document(athleteId)
                .updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])

        } catch {
            errorMessage = "Failed to delete athlete."
            throw error
        }
    }

    // MARK: - Seasons Sync

    /// Creates a new season in Firestore for cross-device sync
    /// - Parameters:
    ///   - userId: The user ID who owns this season
    ///   - data: Season data dictionary (from Season.toFirestoreData())
    /// - Returns: The Firestore document ID for the created season
    func createSeason(userId: String, data: [String: Any]) async throws -> String {

        var seasonData = data
        seasonData["createdAt"] = FieldValue.serverTimestamp()
        seasonData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            let docRef = try await db
                .collection("users")
                .document(userId)
                .collection("seasons")
                .addDocument(data: seasonData)

            return docRef.documentID
        } catch {
            errorMessage = "Failed to create season."
            throw error
        }
    }

    /// Updates an existing season in Firestore
    /// - Parameters:
    ///   - userId: The user ID who owns this season
    ///   - seasonId: The Firestore document ID of the season
    ///   - data: Updated season data dictionary
    func updateSeason(userId: String, seasonId: String, data: [String: Any]) async throws {

        var updateData = data
        updateData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("seasons")
                .document(seasonId)
                .setData(updateData, merge: true)

        } catch {
            errorMessage = "Failed to update season."
            throw error
        }
    }

    /// Fetches all seasons for a user from Firestore
    /// - Parameter userId: The user ID to fetch seasons for
    /// - Returns: Array of FirestoreSeason objects
    func fetchSeasons(userId: String) async throws -> [FirestoreSeason] {

        do {
            let snapshot = try await db
                .collection("users")
                .document(userId)
                .collection("seasons")
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()

            let seasons = snapshot.documents.compactMap { doc -> FirestoreSeason? in
                do {
                    var season = try doc.data(as: FirestoreSeason.self)
                    season.id = doc.documentID
                    return season
                } catch {
                    firestoreLog.warning("Failed to decode FirestoreSeason from doc \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }

            return seasons
        } catch {
            errorMessage = "Failed to fetch seasons."
            throw error
        }
    }

    /// Soft deletes a season in Firestore
    /// - Parameters:
    ///   - userId: The user ID who owns this season
    ///   - seasonId: The Firestore document ID of the season
    func deleteSeason(userId: String, seasonId: String) async throws {

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("seasons")
                .document(seasonId)
                .updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])

        } catch {
            errorMessage = "Failed to delete season."
            throw error
        }
    }

    // MARK: - Games Sync

    /// Creates a new game in Firestore for cross-device sync
    /// - Parameters:
    ///   - userId: The user ID who owns this game
    ///   - data: Game data dictionary (from Game.toFirestoreData())
    /// - Returns: The Firestore document ID for the created game
    func createGame(userId: String, data: [String: Any]) async throws -> String {

        var gameData = data
        gameData["createdAt"] = FieldValue.serverTimestamp()
        gameData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            let docRef = try await db
                .collection("users")
                .document(userId)
                .collection("games")
                .addDocument(data: gameData)

            return docRef.documentID
        } catch {
            errorMessage = "Failed to create game."
            throw error
        }
    }

    /// Updates an existing game in Firestore
    /// - Parameters:
    ///   - userId: The user ID who owns this game
    ///   - gameId: The Firestore document ID of the game
    ///   - data: Updated game data dictionary
    func updateGame(userId: String, gameId: String, data: [String: Any]) async throws {

        var updateData = data
        updateData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("games")
                .document(gameId)
                .setData(updateData, merge: true)

        } catch {
            errorMessage = "Failed to update game."
            throw error
        }
    }

    /// Fetches all games for a user from Firestore
    /// - Parameter userId: The user ID to fetch games for
    /// - Returns: Array of FirestoreGame objects
    func fetchGames(userId: String) async throws -> [FirestoreGame] {

        do {
            let snapshot = try await db
                .collection("users")
                .document(userId)
                .collection("games")
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "date", descending: true)
                .limit(to: 200)
                .getDocuments()

            let games = snapshot.documents.compactMap { doc -> FirestoreGame? in
                do {
                    var game = try doc.data(as: FirestoreGame.self)
                    game.id = doc.documentID
                    return game
                } catch {
                    firestoreLog.warning("Failed to decode FirestoreGame from doc \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }

            return games
        } catch {
            errorMessage = "Failed to fetch games."
            throw error
        }
    }

    /// Soft deletes a game in Firestore
    /// - Parameters:
    ///   - userId: The user ID who owns this game
    ///   - gameId: The Firestore document ID of the game
    func deleteGame(userId: String, gameId: String) async throws {

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("games")
                .document(gameId)
                .updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])

        } catch {
            errorMessage = "Failed to delete game."
            throw error
        }
    }

    /// Soft deletes a video clip's metadata in Firestore
    /// - Parameter videoClipId: The Firestore document ID of the video clip (typically the clip's UUID string)
    func deleteVideoClip(videoClipId: String) async throws {

        do {
            try await db
                .collection("videos")
                .document(videoClipId)
                .updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])

        } catch {
            errorMessage = "Failed to delete video clip metadata."
            throw error
        }
    }

    // MARK: - Practices Sync

    /// Creates a new practice in Firestore for cross-device sync
    /// - Parameters:
    ///   - userId: The user ID who owns this practice
    ///   - data: Practice data dictionary (from Practice.toFirestoreData())
    /// - Returns: The Firestore document ID for the created practice
    func createPractice(userId: String, data: [String: Any]) async throws -> String {

        var practiceData = data
        practiceData["createdAt"] = FieldValue.serverTimestamp()
        practiceData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            let docRef = try await db
                .collection("users")
                .document(userId)
                .collection("practices")
                .addDocument(data: practiceData)

            return docRef.documentID
        } catch {
            errorMessage = "Failed to create practice."
            throw error
        }
    }

    /// Updates an existing practice in Firestore
    /// - Parameters:
    ///   - userId: The user ID who owns this practice
    ///   - practiceId: The Firestore document ID of the practice
    ///   - data: Updated practice data dictionary
    func updatePractice(userId: String, practiceId: String, data: [String: Any]) async throws {

        var updateData = data
        updateData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("practices")
                .document(practiceId)
                .setData(updateData, merge: true)

        } catch {
            errorMessage = "Failed to update practice."
            throw error
        }
    }

    /// Fetches all practices for a user from Firestore
    /// - Parameter userId: The user ID to fetch practices for
    /// - Returns: Array of FirestorePractice objects
    func fetchPractices(userId: String) async throws -> [FirestorePractice] {

        do {
            let snapshot = try await db
                .collection("users")
                .document(userId)
                .collection("practices")
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "date", descending: true)
                .limit(to: 200)
                .getDocuments()

            let practices = snapshot.documents.compactMap { doc -> FirestorePractice? in
                do {
                    var practice = try doc.data(as: FirestorePractice.self)
                    practice.id = doc.documentID
                    return practice
                } catch {
                    firestoreLog.warning("Failed to decode FirestorePractice from doc \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }

            return practices
        } catch {
            errorMessage = "Failed to load practices."
            throw error
        }
    }

    /// Soft deletes a practice in Firestore (marks as deleted, doesn't remove)
    /// - Parameters:
    ///   - userId: The user ID who owns this practice
    ///   - practiceId: The Firestore document ID of the practice
    func deletePractice(userId: String, practiceId: String) async throws {

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("practices")
                .document(practiceId)
                .updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])

        } catch {
            errorMessage = "Failed to delete practice."
            throw error
        }
    }

    // MARK: - Practice Notes Sync

    func deletePracticeNote(userId: String, practiceFirestoreId: String, noteId: String) async throws {
        try await db
            .collection("users").document(userId)
            .collection("practices").document(practiceFirestoreId)
            .collection("notes").document(noteId)
            .updateData([
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }

    func createPracticeNote(userId: String, practiceFirestoreId: String, data: [String: Any]) async throws -> String {
        var noteData = data
        noteData["createdAt"] = FieldValue.serverTimestamp()
        noteData["updatedAt"] = FieldValue.serverTimestamp()
        let docRef = try await db
            .collection("users").document(userId)
            .collection("practices").document(practiceFirestoreId)
            .collection("notes")
            .addDocument(data: noteData)
        return docRef.documentID
    }

    func updatePracticeNote(userId: String, practiceFirestoreId: String, noteId: String, data: [String: Any]) async throws {
        var updateData = data
        updateData["updatedAt"] = FieldValue.serverTimestamp()
        try await db
            .collection("users").document(userId)
            .collection("practices").document(practiceFirestoreId)
            .collection("notes").document(noteId)
            .setData(updateData, merge: true)
    }

    func fetchPracticeNotes(userId: String, practiceFirestoreId: String) async throws -> [FirestorePracticeNote] {
        let snapshot = try await db
            .collection("users").document(userId)
            .collection("practices").document(practiceFirestoreId)
            .collection("notes")
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 100)
            .getDocuments()
        return snapshot.documents.compactMap { doc -> FirestorePracticeNote? in
            do {
                var note = try doc.data(as: FirestorePracticeNote.self)
                note.id = doc.documentID
                return note
            } catch {
                firestoreLog.warning("Failed to decode FirestorePracticeNote from doc \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: - Photos Sync

    func deletePhoto(photoId: String) async throws {
        try await db.collection("photos").document(photoId)
            .updateData([
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }

    func createPhoto(data: [String: Any]) async throws -> String {
        var photoData = data
        photoData["createdAt"] = FieldValue.serverTimestamp()
        photoData["updatedAt"] = FieldValue.serverTimestamp()
        let docRef = try await db.collection("photos").addDocument(data: photoData)
        return docRef.documentID
    }

    func fetchPhotos(uploadedBy ownerUID: String, athleteId: String) async throws -> [FirestorePhoto] {
        let snapshot = try await db
            .collection("photos")
            .whereField("uploadedBy", isEqualTo: ownerUID)
            .whereField("athleteId", isEqualTo: athleteId)
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 100)
            .getDocuments()
        return snapshot.documents.compactMap { doc -> FirestorePhoto? in
            do {
                var photo = try doc.data(as: FirestorePhoto.self)
                photo.id = doc.documentID
                return photo
            } catch {
                firestoreLog.warning("Failed to decode FirestorePhoto from doc \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: - Coaches Sync

    func createCoach(userId: String, athleteFirestoreId: String, data: [String: Any]) async throws -> String {
        var coachData = data
        coachData["createdAt"] = FieldValue.serverTimestamp()
        coachData["updatedAt"] = FieldValue.serverTimestamp()
        let docRef = try await db
            .collection("users").document(userId)
            .collection("athletes").document(athleteFirestoreId)
            .collection("coaches")
            .addDocument(data: coachData)
        return docRef.documentID
    }

    func updateCoach(userId: String, athleteFirestoreId: String, coachId: String, data: [String: Any]) async throws {
        var updateData = data
        updateData["updatedAt"] = FieldValue.serverTimestamp()
        try await db
            .collection("users").document(userId)
            .collection("athletes").document(athleteFirestoreId)
            .collection("coaches").document(coachId)
            .setData(updateData, merge: true)
    }

    func deleteCoach(userId: String, athleteFirestoreId: String, coachId: String) async throws {
        try await db
            .collection("users").document(userId)
            .collection("athletes").document(athleteFirestoreId)
            .collection("coaches").document(coachId)
            .updateData([
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }

    func fetchCoaches(userId: String, athleteFirestoreId: String) async throws -> [FirestoreCoach] {
        let snapshot = try await db
            .collection("users").document(userId)
            .collection("athletes").document(athleteFirestoreId)
            .collection("coaches")
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 50)
            .getDocuments()
        return snapshot.documents.compactMap { doc -> FirestoreCoach? in
            do {
                var coach = try doc.data(as: FirestoreCoach.self)
                coach.id = doc.documentID
                return coach
            } catch {
                firestoreLog.warning("Failed to decode FirestoreCoach from doc \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        }
    }
}
