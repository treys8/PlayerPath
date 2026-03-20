//
//  FirestoreManager+SharedFolders.swift
//  PlayerPath
//
//  Shared folder operations for FirestoreManager
//

import Foundation
import FirebaseFirestore
import os

extension FirestoreManager {

    // MARK: - Shared Folders

    /// Creates a new shared folder for an athlete
    /// - Parameters:
    ///   - name: Display name for the folder (e.g., "Coach Smith")
    ///   - ownerAthleteID: User ID of the athlete creating the folder
    ///   - permissions: Dictionary of coach IDs to their permissions
    /// - Returns: The created folder ID
    func createSharedFolder(
        name: String,
        ownerAthleteID: String,
        permissions: [String: FolderPermissions] = [:]
    ) async throws -> String {
        let folderData: [String: Any] = [
            "name": name,
            "ownerAthleteID": ownerAthleteID,
            "sharedWithCoachIDs": Array(permissions.keys),
            "permissions": permissions.mapValues { $0.toDictionary() },
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "videoCount": 0
        ]

        do {
            let docRef = try await db.collection("sharedFolders").addDocument(data: folderData)
            return docRef.documentID
        } catch {
            errorMessage = "Failed to create folder."
            throw error
        }
    }

    /// Fetches all shared folders owned by an athlete
    func fetchSharedFolders(forAthlete athleteID: String) async throws -> [SharedFolder] {
        do {
            let snapshot = try await db.collection("sharedFolders")
                .whereField("ownerAthleteID", isEqualTo: athleteID)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            let folders = snapshot.documents.compactMap { doc -> SharedFolder? in
                do {
                    var folder = try doc.data(as: SharedFolder.self)
                    folder.id = doc.documentID
                    return folder
                } catch {
                    firestoreLog.warning("Failed to decode SharedFolder from doc \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }

            return folders
        } catch {
            errorMessage = "Failed to load folders."
            throw error
        }
    }

    /// Fetches all shared folders that a coach has access to
    func fetchSharedFolders(forCoach coachID: String) async throws -> [SharedFolder] {

        do {
            let snapshot = try await db.collection("sharedFolders")
                .whereField("sharedWithCoachIDs", arrayContains: coachID)
                .order(by: "updatedAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            let folders = snapshot.documents.compactMap { doc -> SharedFolder? in
                do {
                    var folder = try doc.data(as: SharedFolder.self)
                    folder.id = doc.documentID
                    return folder
                } catch {
                    firestoreLog.warning("Failed to decode SharedFolder from doc \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }

            return folders
        } catch {
            errorMessage = "Failed to load folders."
            throw error
        }
    }

    /// Verifies that a user still has access to a shared folder.
    /// Returns `true` if `sharedWithCoachIDs` contains `userID`, `false` otherwise.
    /// Throws if the folder document cannot be fetched.
    func verifyFolderAccess(folderID: String, userID: String) async throws -> Bool {
        let doc = try await db.collection("sharedFolders").document(folderID).getDocument()
        guard let data = doc.data(),
              let coachIDs = data["sharedWithCoachIDs"] as? [String] else {
            return false
        }
        return coachIDs.contains(userID)
    }

    /// Fetches a single shared folder by ID with latest permissions
    func fetchSharedFolder(folderID: String) async throws -> SharedFolder? {
        do {
            let doc = try await db.collection("sharedFolders").document(folderID).getDocument()

            guard doc.exists else {
                return nil
            }

            do {
                var folder = try doc.data(as: SharedFolder.self)
                folder.id = doc.documentID
                return folder
            } catch {
                firestoreLog.warning("Failed to decode SharedFolder from doc \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        } catch {
            throw error
        }
    }

    /// Removes a coach from a shared folder.
    /// Pass `folderName`, `coachEmail`, and `athleteID` when already available at the call
    /// site to skip 2 redundant Firestore reads (folder doc + coach user doc).
    func removeCoachFromFolder(
        folderID: String,
        coachID: String,
        folderName: String? = nil,
        coachEmail: String? = nil,
        athleteID: String? = nil
    ) async throws {

        let folderRef = db.collection("sharedFolders").document(folderID)

        do {
            // Resolve folderName + athleteID — skip fetch if caller supplied them
            let resolvedFolderName: String
            let resolvedAthleteID: String
            if let fn = folderName, let aid = athleteID {
                resolvedFolderName = fn
                resolvedAthleteID = aid
            } else {
                let folderSnapshot = try await folderRef.getDocument()
                guard let folderData = folderSnapshot.data(),
                      let fn = folderData["name"] as? String,
                      let aid = folderData["ownerAthleteID"] as? String else {
                    throw NSError(domain: "FirestoreManager", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to fetch folder details"])
                }
                resolvedFolderName = fn
                resolvedAthleteID = aid
            }

            // Resolve coachEmail — skip fetch if caller supplied it
            let resolvedCoachEmail: String
            if let ce = coachEmail {
                resolvedCoachEmail = ce
            } else {
                let coachSnapshot = try await db.collection("users").document(coachID).getDocument()
                guard let coachData = coachSnapshot.data(),
                      let ce = coachData["email"] as? String else {
                    throw NSError(domain: "FirestoreManager", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to fetch coach email"])
                }
                resolvedCoachEmail = ce
            }

            // Athlete display name still requires a fetch — not available from any call site
            let athleteSnapshot = try await db.collection("users").document(resolvedAthleteID).getDocument()
            let athleteName = athleteSnapshot.data()?["fullName"] as? String ?? "An athlete"

            // Batch: remove coach from folder + create revocation doc atomically
            let batch = db.batch()

            batch.updateData([
                "sharedWithCoachIDs": FieldValue.arrayRemove([coachID]),
                "permissions.\(coachID)": FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: folderRef)

            let revocationRef = db.collection("coach_access_revocations").document()
            batch.setData([
                "folderID": folderID,
                "folderName": resolvedFolderName,
                "coachID": coachID,
                "coachEmail": resolvedCoachEmail,
                "athleteID": resolvedAthleteID,
                "athleteName": athleteName,
                "revokedAt": FieldValue.serverTimestamp(),
                "emailSent": false
            ], forDocument: revocationRef)

            try await batch.commit()

        } catch {
            errorMessage = "Failed to remove coach."
            throw error
        }
    }

    /// Deletes a shared folder (athlete only)
    func deleteSharedFolder(folderID: String) async throws {
        do {
            // Delete all videos in the folder (paginated — delete until none remain)
            let videosQuery = db.collection("videos")
                .whereField("sharedFolderID", isEqualTo: folderID)
            while true {
                let videosSnapshot = try await videosQuery.limit(to: 400).getDocuments()
                guard !videosSnapshot.documents.isEmpty else { break }
                let batch = db.batch()
                videosSnapshot.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }

            // Then delete the folder
            try await db.collection("sharedFolders").document(folderID).delete()

        } catch {
            errorMessage = "Failed to delete folder."
            throw error
        }
    }
}
