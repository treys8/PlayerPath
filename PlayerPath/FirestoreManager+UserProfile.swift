//
//  FirestoreManager+UserProfile.swift
//  PlayerPath
//
//  User profile operations for FirestoreManager
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import StoreKit
import os

extension FirestoreManager {

    // MARK: - User Profile

    /// Fetches a user profile by ID
    func fetchUserProfile(userID: String) async throws -> UserProfile? {
        let doc = try await db.collection(FC.users).document(userID).getDocument()
        guard doc.exists, let data = doc.data() else { return nil }

        do {
            var profile = try doc.data(as: UserProfile.self)
            profile.id = doc.documentID
            return profile
        } catch {
            // Codable decoding failed — build a profile from raw fields so we
            // don't lose the user's role (e.g. coach) by falling through to
            // the default-athlete fallback in loadUserProfile().
            firestoreLog.warning("Failed to decode UserProfile from doc \(doc.documentID): \(error.localizedDescription). Falling back to manual parsing.")
            let email = data["email"] as? String ?? ""
            let role = data["role"] as? String ?? UserRole.athlete.rawValue
            let profile = UserProfile(
                id: doc.documentID,
                email: email,
                role: role,
                subscriptionTier: data["subscriptionTier"] as? String,
                coachSubscriptionTier: data["coachSubscriptionTier"] as? String,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
            )
            return profile
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

        // Strip non-default subscription/billing fields — upgrades go through syncSubscriptionTiers().
        // Default values ("free", "coach_free") are allowed through so initial profile creation
        // satisfies the Firestore security rule requiring subscriptionTier == "free" on create.
        let defaultTierValues: Set<String> = ["free", "coach_free"]
        let safeProfileData = profileData.filter { key, value in
            if key == "subscriptionTier" || key == "coachSubscriptionTier" {
                return defaultTierValues.contains(value as? String ?? "")
            }
            return true
        }

        // Merge additional profile data; keep explicitly set fields (email, role) on conflict
        userData.merge(safeProfileData) { current, _ in current }

        do {
            try await db.collection(FC.users).document(userID).setData(userData, merge: true)
        } catch {
            firestoreLog.error("Failed to update profile: \(error.localizedDescription)")
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
        hasAthleteTierOverride: Bool = false
    ) async {
        do {
            try await syncSubscriptionTiersWithThrow(
                userID: userID,
                hasAthleteTierOverride: hasAthleteTierOverride
            )
        } catch {
            firestoreLog.warning("Failed to sync subscription tier: \(error.localizedDescription)")
        }
    }

    /// Throwing variant for use with retry logic.
    /// The server derives tiers from verified Transaction JWS tokens —
    /// the client no longer sends tier strings.
    func syncSubscriptionTiersWithThrow(
        userID: String,
        hasAthleteTierOverride: Bool = false
    ) async throws {
        // Obtain the AppTransaction JWS (app-level authenticity proof)
        guard let appReceipt = await appStoreReceipt() else {
            #if DEBUG
            // In sandbox/Xcode testing, AppTransaction is unavailable but individual
            // Transaction JWS tokens still work. Call the Cloud Function in sandboxMode
            // to skip AppTransaction verification while still validating entitlements.
            firestoreLog.info("No App Store receipt (DEBUG). Calling syncSubscriptionTier in sandbox mode.")
            let tokens = await currentEntitlementTokens()
            let payload: [String: Any] = [
                "sandboxMode": true,
                "transactionTokens": tokens,
                "hasAthleteTierOverride": hasAthleteTierOverride
            ]
            do {
                try await callSyncTierFunction(payload: payload)
                firestoreLog.info("DEBUG sandbox tier sync succeeded via Cloud Function.")
            } catch {
                firestoreLog.warning("DEBUG sandbox tier sync failed: \(error.localizedDescription)")
            }
            #else
            firestoreLog.warning("No App Store receipt available. Tier sync skipped.")
            #endif
            return
        }

        // Collect JWS tokens from all current entitlements so the server
        // can verify each transaction and derive tiers from product IDs.
        let transactionTokens = await currentEntitlementTokens()

        let payload: [String: Any] = [
            "receiptData": appReceipt,
            "transactionTokens": transactionTokens,
            "hasAthleteTierOverride": hasAthleteTierOverride
        ]

        try await callSyncTierFunction(payload: payload)
    }

    /// Calls syncSubscriptionTier via direct URLSession instead of HTTPSCallable.call()
    /// to avoid Firebase SDK async let crash on iOS 26.
    private func callSyncTierFunction(payload: [String: Any]) async throws {
        guard let user = Auth.auth().currentUser else { return }
        let token = try await user.getIDToken()

        let url = URL(string: "https://us-central1-playerpath-159b2.cloudfunctions.net/syncSubscriptionTier")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": payload])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "FirestoreManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Tier sync failed"])
        }
    }

    /// Returns the StoreKit 2 JWS app transaction token for server-side validation.
    fileprivate func appStoreReceipt() async -> String? {
        if let result = try? await AppTransaction.shared {
            return result.jwsRepresentation
        }
        return nil
    }

    /// Collects JWS representations from all current subscription entitlements.
    /// The server verifies these independently to derive the user's actual tier.
    fileprivate func currentEntitlementTokens() async -> [String] {
        var tokens: [String] = []
        for await result in Transaction.currentEntitlements {
            // jwsRepresentation is on the VerificationResult envelope
            tokens.append(result.jwsRepresentation)
        }
        return tokens
    }

    /// Deletes user profile and all associated data (GDPR compliance)
    ///
    /// Deletion proceeds step-by-step. Each step is wrapped in its own error handler
    /// so that a failure in one category does not prevent deletion of other categories.
    /// A partial deletion is better than no deletion for GDPR compliance.
    func deleteUserProfile(userID: String) async throws {
        var stepErrors: [String] = []

        // Fetch user email for email-based invitation cleanup (GDPR)
        var userEmail: String?
        do {
            let userDoc = try await db.collection(FC.users).document(userID).getDocument()
            userEmail = userDoc.data()?["email"] as? String
        } catch {
            stepErrors.append("email lookup: \(error.localizedDescription)")
        }

        // MARK: Step 1 — Delete shared folders owned by this user (+ their videos + annotations)
        do {
            let foldersQuery = db.collection(FC.sharedFolders)
                .whereField("ownerAthleteID", isEqualTo: userID)
            while true {
                let foldersSnapshot = try await foldersQuery.limit(to: 50).getDocuments()
                guard !foldersSnapshot.documents.isEmpty else { break }
                for folderDoc in foldersSnapshot.documents {
                    let folderID = folderDoc.documentID
                    let videosQuery = db.collection(FC.videos)
                        .whereField("sharedFolderID", isEqualTo: folderID)
                    while true {
                        let videosSnapshot = try await videosQuery.limit(to: 100).getDocuments()
                        guard !videosSnapshot.documents.isEmpty else { break }
                        for videoDoc in videosSnapshot.documents {
                            // Delete annotations for this video (paginated)
                            let annotationsQuery = db.collection(FC.videos)
                                .document(videoDoc.documentID)
                                .collection(FC.annotations)
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
                    try await db.collection(FC.sharedFolders).document(folderID).delete()
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

        // MARK: Step 2b — Delete all comments authored by this user across all videos
        do {
            let userCommentsQuery = db.collectionGroup(FC.comments)
                .whereField("authorId", isEqualTo: userID)
            while true {
                let snap = try await userCommentsQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        } catch {
            stepErrors.append("comments: \(error.localizedDescription)")
        }

        // MARK: Step 2c — Delete all drill cards created by this user across all videos
        do {
            let userDrillCardsQuery = db.collectionGroup(FC.drillCards)
                .whereField("coachID", isEqualTo: userID)
            while true {
                let snap = try await userDrillCardsQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        } catch {
            stepErrors.append("drill cards: \(error.localizedDescription)")
        }

        // MARK: Step 2d — Delete coach sessions created by this user
        do {
            let coachSessionsQuery = db.collection(FC.coachSessions)
                .whereField("coachID", isEqualTo: userID)
            while true {
                let snap = try await coachSessionsQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        } catch {
            stepErrors.append("coach sessions: \(error.localizedDescription)")
        }

        // MARK: Step 2e — Delete coach templates (quick cues)
        do {
            let quickCuesQuery = db.collection(FC.coachTemplates)
                .document(userID)
                .collection(FC.quickCues)
            while true {
                let snap = try await quickCuesQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
            // Delete the parent coachTemplates document
            try await db.collection(FC.coachTemplates).document(userID).delete()
        } catch {
            stepErrors.append("coach templates: \(error.localizedDescription)")
        }

        // MARK: Step 3 — Delete invitations where user is the athlete
        do {
            let athleteInvitationsQuery = db.collection(FC.invitations)
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
            let coachInvitationsQuery = db.collection(FC.invitations)
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

        // MARK: Step 4b — Delete invitations containing user's email (GDPR right to erasure)
        if let email = userEmail?.lowercased() {
            for field in ["coachEmail", "athleteEmail"] {
                do {
                    let emailInvQuery = db.collection(FC.invitations)
                        .whereField(field, isEqualTo: email)
                    while true {
                        let snap = try await emailInvQuery.limit(to: 400).getDocuments()
                        guard !snap.documents.isEmpty else { break }
                        let batch = db.batch()
                        snap.documents.forEach { batch.deleteDocument($0.reference) }
                        try await batch.commit()
                    }
                } catch {
                    stepErrors.append("\(field) invitations: \(error.localizedDescription)")
                }
            }
        }

        // MARK: Step 5 — Delete notifications
        do {
            let notificationsQuery = db.collection(FC.notifications)
                .document(userID)
                .collection(FC.items)
            while true {
                let snap = try await notificationsQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
            try await db.collection(FC.notifications).document(userID).delete()
        } catch {
            stepErrors.append("notifications: \(error.localizedDescription)")
        }

        // MARK: Step 6 — Delete coach_access_revocations referencing this user
        do {
            for field in ["athleteID", "coachID"] {
                let revocationsQuery = db.collection(FC.coachAccessRevocations)
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
            let coachFoldersQuery = db.collection(FC.sharedFolders)
                .whereField("sharedWithCoachIDs", arrayContains: userID)
            while true {
                let coachFoldersSnap = try await coachFoldersQuery.limit(to: 50).getDocuments()
                guard !coachFoldersSnap.documents.isEmpty else { break }
                for folderDoc in coachFoldersSnap.documents {
                    try await folderDoc.reference.updateData([
                        "sharedWithCoachIDs": FieldValue.arrayRemove([userID]),
                        "sharedWithCoachNames.\(userID)": FieldValue.delete(),
                        "permissions.\(userID)": FieldValue.delete(),
                        "updatedAt": FieldValue.serverTimestamp()
                    ])
                }
            }
        } catch {
            stepErrors.append("coach folder cleanup: \(error.localizedDescription)")
        }

        // MARK: Step 8 — Mark videos uploaded by user to others' folders as orphaned
        // updateData is idempotent so re-processing is safe if this runs twice.
        // Cursor-based pagination because updated docs still match the query.
        do {
            let uploadedVideosQuery = db.collection(FC.videos)
                .whereField("uploadedBy", isEqualTo: userID)
            var lastDoc: QueryDocumentSnapshot?
            while true {
                var pageQuery = uploadedVideosQuery.order(by: "__name__").limit(to: 400)
                if let lastDoc { pageQuery = pageQuery.start(afterDocument: lastDoc) }
                let snap = try await pageQuery.getDocuments()
                guard !snap.documents.isEmpty else { break }
                lastDoc = snap.documents.last
                let batch = db.batch()
                for doc in snap.documents {
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
            let photosQuery = db.collection(FC.photos)
                .whereField("uploadedBy", isEqualTo: userID)
            while true {
                let snap = try await photosQuery.order(by: "__name__").limit(to: 400).getDocuments()
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
            // Fetch and delete athlete documents for this user (paginated — deleted docs fall out of query)
            let athletesBaseQuery = db.collection(FC.users).document(userID).collection(FC.athletes)
            while true {
                let athletesSnap = try await athletesBaseQuery.order(by: "__name__").limit(to: 50).getDocuments()
                guard !athletesSnap.documents.isEmpty else { break }

                for athleteDoc in athletesSnap.documents {
                    let athleteRef = athleteDoc.reference

                    // Delete coaches subcollection
                    let coachesQuery = athleteRef.collection(FC.coaches)
                    while true {
                        let snap = try await coachesQuery.order(by: "__name__").limit(to: 400).getDocuments()
                        guard !snap.documents.isEmpty else { break }
                        let batch = db.batch()
                        snap.documents.forEach { batch.deleteDocument($0.reference) }
                        try await batch.commit()
                    }

                    // Delete athlete document
                    try await athleteRef.delete()
                }
            }

            // Delete practices (with nested notes)
            let practicesQuery = db.collection(FC.users).document(userID).collection(FC.practices)
            while true {
                let snap = try await practicesQuery.limit(to: 100).getDocuments()
                guard !snap.documents.isEmpty else { break }
                for practiceDoc in snap.documents {
                    // Delete notes subcollection
                    let notesQuery = practiceDoc.reference.collection(FC.notes)
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
            let gamesQuery = db.collection(FC.users).document(userID).collection(FC.games)
            while true {
                let snap = try await gamesQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }

            // Delete seasons
            let seasonsQuery = db.collection(FC.users).document(userID).collection(FC.seasons)
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
            let pendingQuery = db.collection(FC.pendingDeletions)
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
            try await db.collection(FC.users).document(userID).delete()
        } catch {
            // Profile deletion is critical — if this fails, throw
            firestoreLog.error("Failed to delete user profile for \(userID): \(error.localizedDescription)")
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
            let doc = try await db.collection(FC.users).document(coachID).getDocument()

            guard doc.exists else {
                throw NSError(
                    domain: "FirestoreManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Coach not found"]
                )
            }

            let data = doc.data() ?? [:]
            let email = data["email"] as? String ?? "Unknown"
            let displayName = data["displayName"] as? String

            let name = displayName ?? email.components(separatedBy: "@").first ?? "Unknown Coach"

            return (name: name, email: email)
        } catch {
            firestoreLog.error("Failed to fetch coach info for \(coachID): \(error.localizedDescription)")
            throw error
        }
    }
}
