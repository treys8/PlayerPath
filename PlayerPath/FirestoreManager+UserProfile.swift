//
//  FirestoreManager+UserProfile.swift
//  PlayerPath
//
//  User profile operations for FirestoreManager
//

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import StoreKit
import os

extension FirestoreManager {

    // MARK: - User Profile

    /// Fetches a user profile by ID
    func fetchUserProfile(userID: String) async throws -> UserProfile? {
        do {
            let doc = try await db.collection("users").document(userID).getDocument()
            do {
                var profile = try doc.data(as: UserProfile.self)
                profile.id = doc.documentID
                return profile
            } catch {
                firestoreLog.warning("Failed to decode UserProfile from doc \(doc.documentID): \(error.localizedDescription)")
                return nil
            }
        } catch {
            throw error
        }
    }

    /// Updates or creates a user profile
    func updateUserProfile(
        userID: String,
        email: String,
        role: UserRole,
        profileData: [String: Any]
    ) async throws {
        var userData: [String: Any] = [
            "email": email.lowercased(),
            "role": role.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        // Strip subscription/billing fields from general profile updates — use syncSubscriptionTiers() for tier writes
        let serverOnlyFields: Set<String> = ["subscriptionTier", "coachSubscriptionTier"]
        let safeProfileData = profileData.filter { !serverOnlyFields.contains($0.key) }

        // Merge additional profile data; keep explicitly set fields (email, role) on conflict
        userData.merge(safeProfileData) { current, _ in current }

        do {
            try await db.collection("users").document(userID).setData(userData, merge: true)
        } catch {
            errorMessage = "Failed to update profile."
            throw error
        }
    }

    /// Syncs StoreKit-resolved subscription tiers to the user's Firestore doc
    /// via the `syncSubscriptionTier` Cloud Function, which validates the App Store
    /// receipt server-side before writing. This prevents clients from bypassing
    /// StoreKit by writing tier values directly to Firestore.
    func syncSubscriptionTiers(
        userID: String,
        tier: SubscriptionTier,
        coachTier: CoachSubscriptionTier,
        hasAthleteTierOverride: Bool = false,
        receiptData: String? = nil
    ) async {
        // Obtain the App Store receipt/transaction token if not provided
        let receipt: String
        if let provided = receiptData {
            receipt = provided
        } else if let jwsToken = await appTransactionJWS() {
            receipt = jwsToken
        } else {
            return
        }

        let callable = Functions.functions().httpsCallable("syncSubscriptionTier")
        let payload: [String: Any] = [
            "receiptData": receipt,
            "tier": tier.rawValue,
            "coachTier": coachTier.rawValue,
            "hasAthleteTierOverride": hasAthleteTierOverride
        ]

        do {
            let _ = try await callable.call(payload)
        } catch {
            firestoreLog.warning("Failed to sync subscription tier to server: \(error.localizedDescription)")
        }
    }

    /// Returns the signed JWS string from AppTransaction, or nil on failure.
    fileprivate func appTransactionJWS() async -> String? {
        guard let result = try? await AppTransaction.shared else {
            return nil
        }
        return result.jwsRepresentation
    }

    /// Deletes user profile and all associated data (GDPR compliance)
    ///
    /// Deletion proceeds step-by-step. Each step is wrapped in its own error handler
    /// so that a failure in one category does not prevent deletion of other categories.
    /// A partial deletion is better than no deletion for GDPR compliance.
    func deleteUserProfile(userID: String) async throws {
        var stepErrors: [String] = []

        // MARK: Step 1 — Delete shared folders owned by this user (+ their videos + annotations)
        do {
            let foldersQuery = db.collection("sharedFolders")
                .whereField("ownerAthleteID", isEqualTo: userID)
            while true {
                let foldersSnapshot = try await foldersQuery.limit(to: 50).getDocuments()
                guard !foldersSnapshot.documents.isEmpty else { break }
                for folderDoc in foldersSnapshot.documents {
                    let folderID = folderDoc.documentID
                    let videosQuery = db.collection("videos")
                        .whereField("sharedFolderID", isEqualTo: folderID)
                    while true {
                        let videosSnapshot = try await videosQuery.limit(to: 100).getDocuments()
                        guard !videosSnapshot.documents.isEmpty else { break }
                        for videoDoc in videosSnapshot.documents {
                            // Delete annotations for this video (paginated)
                            let annotationsQuery = db.collection("videos")
                                .document(videoDoc.documentID)
                                .collection("annotations")
                            while true {
                                let annSnap = try await annotationsQuery.limit(to: 400).getDocuments()
                                guard !annSnap.documents.isEmpty else { break }
                                let batch = db.batch()
                                annSnap.documents.forEach { batch.deleteDocument($0.reference) }
                                try await batch.commit()
                            }
                            try await videoDoc.reference.delete()
                        }
                    }
                    try await db.collection("sharedFolders").document(folderID).delete()
                }
            }
        } catch {
            stepErrors.append("shared folders: \(error.localizedDescription)")
        }

        // MARK: Step 2 — Delete all annotations created by this user across all videos
        do {
            let userAnnotationsQuery = db.collectionGroup("annotations")
                .whereField("userID", isEqualTo: userID)
            while true {
                let snap = try await userAnnotationsQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        } catch {
            stepErrors.append("annotations: \(error.localizedDescription)")
        }

        // MARK: Step 3 — Delete invitations where user is the athlete
        do {
            let athleteInvitationsQuery = db.collection("invitations")
                .whereField("athleteID", isEqualTo: userID)
            while true {
                let snap = try await athleteInvitationsQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        } catch {
            stepErrors.append("athlete invitations: \(error.localizedDescription)")
        }

        // MARK: Step 4 — Delete invitations where user is the coach
        do {
            let coachInvitationsQuery = db.collection("invitations")
                .whereField("coachID", isEqualTo: userID)
            while true {
                let snap = try await coachInvitationsQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        } catch {
            stepErrors.append("coach invitations: \(error.localizedDescription)")
        }

        // MARK: Step 5 — Delete notifications
        do {
            let notificationsQuery = db.collection("notifications")
                .document(userID)
                .collection("items")
            while true {
                let snap = try await notificationsQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
            try await db.collection("notifications").document(userID).delete()
        } catch {
            stepErrors.append("notifications: \(error.localizedDescription)")
        }

        // MARK: Step 6 — Delete coach_access_revocations referencing this user
        do {
            for field in ["athleteID", "coachID"] {
                let revocationsQuery = db.collection("coach_access_revocations")
                    .whereField(field, isEqualTo: userID)
                while true {
                    let snap = try await revocationsQuery.limit(to: 400).getDocuments()
                    guard !snap.documents.isEmpty else { break }
                    let batch = db.batch()
                    snap.documents.forEach { batch.deleteDocument($0.reference) }
                    try await batch.commit()
                }
            }
        } catch {
            stepErrors.append("access revocations: \(error.localizedDescription)")
        }

        // MARK: Step 7 — Remove user from sharedWithCoachIDs on other users' folders
        do {
            let coachFoldersQuery = db.collection("sharedFolders")
                .whereField("sharedWithCoachIDs", arrayContains: userID)
            let coachFoldersSnap = try await coachFoldersQuery.getDocuments()
            for folderDoc in coachFoldersSnap.documents {
                try await folderDoc.reference.updateData([
                    "sharedWithCoachIDs": FieldValue.arrayRemove([userID]),
                    "permissions.\(userID)": FieldValue.delete(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            }
        } catch {
            stepErrors.append("coach folder cleanup: \(error.localizedDescription)")
        }

        // MARK: Step 8 — Mark videos uploaded by user to others' folders as orphaned
        // Single pass (not paginated delete loop) because we're updating, not removing.
        // updateData is idempotent so re-processing is safe if this runs twice.
        do {
            let uploadedVideosQuery = db.collection("videos")
                .whereField("uploadedBy", isEqualTo: userID)
            let snap = try await uploadedVideosQuery.getDocuments()
            // Batch in groups of 400 to stay within Firestore's 500-operation limit
            let chunks = stride(from: 0, to: snap.documents.count, by: 400)
            for chunkStart in chunks {
                let chunkEnd = min(chunkStart + 400, snap.documents.count)
                let batch = db.batch()
                for doc in snap.documents[chunkStart..<chunkEnd] {
                    batch.updateData([
                        "isOrphaned": true,
                        "orphanedAt": FieldValue.serverTimestamp()
                    ], forDocument: doc.reference)
                }
                try await batch.commit()
            }
        } catch {
            stepErrors.append("orphan videos: \(error.localizedDescription)")
        }

        // MARK: Step 9 — Delete photos uploaded by user
        do {
            let photosQuery = db.collection("photos")
                .whereField("uploadedBy", isEqualTo: userID)
            while true {
                let snap = try await photosQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        } catch {
            stepErrors.append("photos: \(error.localizedDescription)")
        }

        // MARK: Step 10 — Delete user subcollections (bottom-up: notes → practices → games → seasons → coaches → athletes)
        do {
            // Fetch all athlete documents for this user
            let athletesQuery = db.collection("users").document(userID).collection("athletes")
            let athletesSnap = try await athletesQuery.getDocuments()

            for athleteDoc in athletesSnap.documents {
                let athleteRef = athleteDoc.reference

                // Delete coaches subcollection
                let coachesQuery = athleteRef.collection("coaches")
                while true {
                    let snap = try await coachesQuery.limit(to: 400).getDocuments()
                    guard !snap.documents.isEmpty else { break }
                    let batch = db.batch()
                    snap.documents.forEach { batch.deleteDocument($0.reference) }
                    try await batch.commit()
                }

                // Delete athlete document
                try await athleteRef.delete()
            }

            // Delete practices (with nested notes)
            let practicesQuery = db.collection("users").document(userID).collection("practices")
            while true {
                let snap = try await practicesQuery.limit(to: 100).getDocuments()
                guard !snap.documents.isEmpty else { break }
                for practiceDoc in snap.documents {
                    // Delete notes subcollection
                    let notesQuery = practiceDoc.reference.collection("notes")
                    while true {
                        let notesSnap = try await notesQuery.limit(to: 400).getDocuments()
                        guard !notesSnap.documents.isEmpty else { break }
                        let batch = db.batch()
                        notesSnap.documents.forEach { batch.deleteDocument($0.reference) }
                        try await batch.commit()
                    }
                    try await practiceDoc.reference.delete()
                }
            }

            // Delete games
            let gamesQuery = db.collection("users").document(userID).collection("games")
            while true {
                let snap = try await gamesQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }

            // Delete seasons
            let seasonsQuery = db.collection("users").document(userID).collection("seasons")
            while true {
                let snap = try await seasonsQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        } catch {
            stepErrors.append("user subcollections: \(error.localizedDescription)")
        }

        // MARK: Step 11 — Delete pendingDeletions referencing this user
        do {
            let pendingQuery = db.collection("pendingDeletions")
                .whereField("ownerUID", isEqualTo: userID)
            while true {
                let snap = try await pendingQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        } catch {
            stepErrors.append("pending deletions: \(error.localizedDescription)")
        }

        // MARK: Step 12 — Delete Firebase Storage files (best-effort)
        do {
            try await VideoCloudManager.shared.deleteAllUserVideos(userID: userID)
        } catch {
            stepErrors.append("storage videos: \(error.localizedDescription)")
        }
        do {
            try await VideoCloudManager.shared.deleteAllUserPhotos(userID: userID)
        } catch {
            stepErrors.append("storage photos: \(error.localizedDescription)")
        }

        // MARK: Step 13 — Delete user profile document
        do {
            try await db.collection("users").document(userID).delete()
        } catch {
            // Profile deletion is critical — if this fails, throw
            errorMessage = "Failed to delete user profile."
            throw error
        }

        // Log any partial failures
        if !stepErrors.isEmpty {
            firestoreLog.error("GDPR deletion completed with partial failures for user \(userID): \(stepErrors.joined(separator: "; "))")
        }
    }

    /// Fetches coach information (name and email) by ID
    /// Returns a tuple with name and email for display purposes
    func fetchCoachInfo(coachID: String) async throws -> (name: String, email: String) {
        do {
            let doc = try await db.collection("users").document(coachID).getDocument()

            guard doc.exists else {
                throw NSError(
                    domain: "FirestoreManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Coach not found"]
                )
            }

            let data = doc.data() ?? [:]
            let email = data["email"] as? String ?? "Unknown"
            let fullName = data["fullName"] as? String
            let displayName = data["displayName"] as? String

            // Use fullName if available, fallback to displayName, then email
            let name = fullName ?? displayName ?? email.components(separatedBy: "@").first ?? "Unknown Coach"

            return (name: name, email: email)
        } catch {
            firestoreLog.error("Failed to fetch coach info for \(coachID): \(error.localizedDescription)")
            throw error
        }
    }
}
