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
    ///   - ownerAthleteName: Display name of the athlete (shown to coaches)
    ///   - permissions: Dictionary of coach IDs to their permissions
    /// - Returns: The created folder ID
    func createSharedFolder(
        name: String,
        ownerAthleteID: String,
        ownerAthleteName: String? = nil,
        permissions: [String: FolderPermissions] = [:],
        folderType: String? = nil
    ) async throws -> String {
        var folderData: [String: Any] = [
            "name": name,
            "ownerAthleteID": ownerAthleteID,
            "sharedWithCoachIDs": Array(permissions.keys),
            "permissions": permissions.mapValues { $0.toDictionary() },
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "videoCount": 0
        ]
        if let ownerAthleteName {
            folderData["ownerAthleteName"] = ownerAthleteName
        }
        if let folderType {
            folderData["folderType"] = folderType
        }

        do {
            let docRef = try await db.collection(FC.sharedFolders).addDocument(data: folderData)
            return docRef.documentID
        } catch {
            firestoreLog.error("Failed to create folder: \(error.localizedDescription)")
            errorMessage = "Failed to create folder."
            throw error
        }
    }

    /// Fetches all shared folders owned by an athlete
    func fetchSharedFolders(forAthlete athleteID: String) async throws -> [SharedFolder] {
        do {
            let snapshot = try await db.collection(FC.sharedFolders)
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
            firestoreLog.error("Failed to load folders: \(error.localizedDescription)")
            errorMessage = "Failed to load folders."
            throw error
        }
    }

    /// Fetches all shared folders that a coach has access to
    func fetchSharedFolders(forCoach coachID: String) async throws -> [SharedFolder] {

        do {
            let snapshot = try await db.collection(FC.sharedFolders)
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
            firestoreLog.error("Failed to load coach folders: \(error.localizedDescription)")
            errorMessage = "Failed to load folders."
            throw error
        }
    }

    /// Verifies that a user still has access to a shared folder.
    /// Returns `true` if `sharedWithCoachIDs` contains `userID`, `false` otherwise.
    /// Throws if the folder document cannot be fetched.
    func verifyFolderAccess(folderID: String, userID: String) async throws -> Bool {
        let doc = try await db.collection(FC.sharedFolders).document(folderID).getDocument()
        guard let data = doc.data(),
              let coachIDs = data["sharedWithCoachIDs"] as? [String] else {
            return false
        }
        return coachIDs.contains(userID)
    }

    /// Fetches a single shared folder by ID with latest permissions
    func fetchSharedFolder(folderID: String) async throws -> SharedFolder? {
        do {
            let doc = try await db.collection(FC.sharedFolders).document(folderID).getDocument()

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
            firestoreLog.error("Failed to fetch shared folder \(folderID): \(error.localizedDescription)")
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

        let folderRef = db.collection(FC.sharedFolders).document(folderID)

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
                let coachSnapshot = try await db.collection(FC.users).document(coachID).getDocument()
                guard let coachData = coachSnapshot.data(),
                      let ce = coachData["email"] as? String else {
                    throw NSError(domain: "FirestoreManager", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to fetch coach email"])
                }
                resolvedCoachEmail = ce
            }

            // Athlete display name still requires a fetch — not available from any call site
            let athleteSnapshot = try await db.collection(FC.users).document(resolvedAthleteID).getDocument()
            let athleteName = athleteSnapshot.data()?["displayName"] as? String ?? "An athlete"

            // Batch: remove coach from folder + create revocation doc atomically
            let batch = db.batch()

            batch.updateData([
                "sharedWithCoachIDs": FieldValue.arrayRemove([coachID]),
                "sharedWithCoachNames.\(coachID)": FieldValue.delete(),
                "permissions.\(coachID)": FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: folderRef)

            let revocationRef = db.collection(FC.coachAccessRevocations).document()
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
            firestoreLog.error("Failed to remove coach: \(error.localizedDescription)")
            errorMessage = "Failed to remove coach."
            throw error
        }
    }

    /// Deletes a shared folder (athlete only)
    /// - Parameter skipVideoCleanup: If true, skips video/storage deletion (caller already handled it)
    func deleteSharedFolder(folderID: String, skipVideoCleanup: Bool = false) async throws {
        do {
            // Cancel pending invitations referencing this folder
            let invitationsQuery = db.collection(FC.invitations)
                .whereField("folderID", isEqualTo: folderID)
                .whereField("status", isEqualTo: "pending")
            while true {
                let invSnap = try await invitationsQuery.limit(to: 400).getDocuments()
                guard !invSnap.documents.isEmpty else { break }
                let batch = db.batch()
                for doc in invSnap.documents {
                    batch.updateData([
                        "status": "cancelled",
                        "cancelledAt": FieldValue.serverTimestamp()
                    ], forDocument: doc.reference)
                }
                try await batch.commit()
            }

            if !skipVideoCleanup {
                // Delete all videos in the folder: subcollections, Storage files, then Firestore docs
                let videosQuery = db.collection(FC.videos)
                    .whereField("sharedFolderID", isEqualTo: folderID)
                while true {
                    let videosSnapshot = try await videosQuery.limit(to: 400).getDocuments()
                    guard !videosSnapshot.documents.isEmpty else { break }

                    // Track which docs had successful Storage deletion
                    var safeToDeleteDocIDs: Set<String> = []

                    for doc in videosSnapshot.documents {
                        // Clean up subcollections (annotations, comments, drillCards)
                        await deleteVideoSubcollections(videoID: doc.documentID)

                        // Delete Storage files — only mark doc safe to delete if Storage succeeds
                        let data = doc.data()
                        if let fileName = data["fileName"] as? String {
                            var storageDeletedOk = true
                            do {
                                try await VideoCloudManager.shared.deleteVideo(fileName: fileName, folderID: folderID)
                            } catch {
                                firestoreLog.warning("Failed to delete Storage file \(fileName) in folder \(folderID): \(error.localizedDescription)")
                                storageDeletedOk = false
                            }
                            do {
                                try await VideoCloudManager.shared.deleteThumbnail(videoFileName: fileName, folderID: folderID)
                            } catch {
                                // Thumbnail may not exist — ignore
                            }
                            if storageDeletedOk {
                                safeToDeleteDocIDs.insert(doc.documentID)
                            }
                        } else {
                            // No fileName — safe to delete metadata
                            safeToDeleteDocIDs.insert(doc.documentID)
                        }
                    }

                    // Only delete Firestore docs whose Storage files were successfully deleted.
                    // Docs with failed Storage deletes are preserved so a cleanup job can find them.
                    let docsToDelete = videosSnapshot.documents.filter { safeToDeleteDocIDs.contains($0.documentID) }
                    if !docsToDelete.isEmpty {
                        let batch = db.batch()
                        docsToDelete.forEach { batch.deleteDocument($0.reference) }
                        try await batch.commit()
                    }

                    // If some docs couldn't be deleted, log for manual cleanup
                    let orphanedCount = videosSnapshot.documents.count - docsToDelete.count
                    if orphanedCount > 0 {
                        firestoreLog.warning("\(orphanedCount) video doc(s) preserved in folder \(folderID) due to Storage deletion failure")
                    }
                }
            }

            // Then delete the folder
            try await db.collection(FC.sharedFolders).document(folderID).delete()

        } catch {
            firestoreLog.error("Failed to delete folder: \(error.localizedDescription)")
            errorMessage = "Failed to delete folder."
            throw error
        }
    }

    // MARK: - Batch Revocation (Coach Downgrade)

    /// Removes coach access from all folders belonging to the specified athletes
    /// and cancels any accepted invitations for those athletes.
    /// Used when a coach downgrades and must reduce their connected athlete count.
    /// Revokes coach access from folders owned by the specified athletes.
    /// Collects errors per-batch so that a single failure doesn't halt the entire operation.
    /// Returns silently on full success; throws an aggregate error if any batch failed.
    func batchRevokeCoachAccess(
        coachID: String,
        athleteIDsToRevoke: [String]
    ) async throws {
        guard !athleteIDsToRevoke.isEmpty else { return }

        let revokeSet = Set(athleteIDsToRevoke)
        let folders = SharedFolderManager.shared.coachFolders.filter { revokeSet.contains($0.ownerAthleteID) }

        // Fetch coach email once for revocation docs
        let coachSnapshot = try await db.collection(FC.users).document(coachID).getDocument()
        let coachEmail = coachSnapshot.data()?["email"] as? String ?? ""

        var batchErrors: [Error] = []

        // 1. Revoke folder access
        if !folders.isEmpty {
            let batchSize = 250 // 2 operations per folder (update + revocation doc)
            for startIndex in stride(from: 0, to: folders.count, by: batchSize) {
                let chunk = folders[startIndex..<min(startIndex + batchSize, folders.count)]
                let batch = db.batch()

                for folder in chunk {
                    guard let folderID = folder.id else { continue }

                    let folderRef = db.collection(FC.sharedFolders).document(folderID)
                    batch.updateData([
                        "sharedWithCoachIDs": FieldValue.arrayRemove([coachID]),
                        "sharedWithCoachNames.\(coachID)": FieldValue.delete(),
                        "permissions.\(coachID)": FieldValue.delete(),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: folderRef)

                    let revocationRef = db.collection(FC.coachAccessRevocations).document()
                    batch.setData([
                        "folderID": folderID,
                        "folderName": folder.name,
                        "coachID": coachID,
                        "coachEmail": coachEmail,
                        "athleteID": folder.ownerAthleteID,
                        "athleteName": folder.ownerAthleteName ?? "Unknown",
                        "revokedAt": FieldValue.serverTimestamp(),
                        "emailSent": false,
                        "reason": "downgrade"
                    ], forDocument: revocationRef)
                }

                do {
                    try await batch.commit()
                } catch {
                    firestoreLog.error("Batch revocation failed for chunk starting at \(startIndex): \(error.localizedDescription)")
                    batchErrors.append(error)
                }
            }
        }

        // 2. Delete accepted coach-to-athlete invitations for revoked athletes.
        do {
            let c2aSnapshot = try await db.collection(FC.invitations)
                .whereField("type", isEqualTo: "coach_to_athlete")
                .whereField("coachID", isEqualTo: coachID)
                .whereField("status", isEqualTo: "accepted")
                .getDocuments()

            for doc in c2aSnapshot.documents {
                let athleteUID = doc.data()["athleteUserID"] as? String ?? ""
                if revokeSet.contains(athleteUID) {
                    do {
                        try await doc.reference.delete()
                    } catch {
                        firestoreLog.error("Failed to delete coach-to-athlete invitation \(doc.documentID): \(error.localizedDescription)")
                        batchErrors.append(error)
                    }
                }
            }
        } catch {
            firestoreLog.error("Failed to fetch coach-to-athlete invitations for cleanup: \(error.localizedDescription)")
            batchErrors.append(error)
        }

        // 3. Also delete accepted athlete-to-coach invitations for revoked athletes.
        do {
            let a2cSnapshot = try await db.collection(FC.invitations)
                .whereField("type", isEqualTo: "athlete_to_coach")
                .whereField("acceptedByCoachID", isEqualTo: coachID)
                .whereField("status", isEqualTo: "accepted")
                .getDocuments()

            for doc in a2cSnapshot.documents {
                let athleteID = doc.data()["athleteID"] as? String ?? ""
                if revokeSet.contains(athleteID) {
                    do {
                        try await doc.reference.delete()
                    } catch {
                        firestoreLog.error("Failed to delete athlete-to-coach invitation \(doc.documentID): \(error.localizedDescription)")
                        batchErrors.append(error)
                    }
                }
            }
        } catch {
            firestoreLog.error("Failed to fetch athlete-to-coach invitations for cleanup: \(error.localizedDescription)")
            batchErrors.append(error)
        }

        if !batchErrors.isEmpty {
            throw NSError(
                domain: "PlayerPath",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "\(batchErrors.count) operation(s) failed during coach access revocation. Some folders may not have been revoked."]
            )
        }
    }
}
