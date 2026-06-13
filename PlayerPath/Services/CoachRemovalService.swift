//
//  CoachRemovalService.swift
//  PlayerPath
//
//  Shared remote-revoke flow for coach removal. Both CoachesView (swipe) and
//  CoachDetailView (button) call through here so retry/security behavior
//  stays consistent. Silent failure leaves a coach with residual folder
//  access, so both steps retry.
//

import Foundation

enum CoachRemovalService {
    /// Revokes a coach's access to all shared folders and soft-deletes the
    /// Firestore coach record. Both operations use `retryAsync` — a silent
    /// failure here means the coach retains access they shouldn't have.
    ///
    /// Call from a `Task { }` after the local SwiftData delete. This function
    /// does not touch SwiftData; the caller owns local state and UI reaction.
    static func revokeRemoteAccess(
        firebaseCoachID: String?,
        sharedFolderIDs: [String],
        userID: String?,
        athleteFirestoreID: String?,
        coachFirestoreID: String?,
        coachEmail: String? = nil
    ) async {
        if let coachID = firebaseCoachID {
            // Coach.sharedFolderIDs is device-local (never synced), so the cached
            // list can be empty or stale (missing folders shared after it was
            // written). Union it with the authoritative Firestore-derived list
            // rather than silently skipping a revoke.
            var folderIDs = Set(sharedFolderIDs)
            if let userID {
                do {
                    let folders = try await withRetry {
                        try await FirestoreManager.shared.fetchSharedFolders(forAthlete: userID)
                    }
                    folderIDs.formUnion(
                        folders
                            .filter { $0.sharedWithCoachIDs.contains(coachID) || $0.permissions[coachID] != nil }
                            .compactMap { $0.id }
                    )
                } catch {
                    ErrorHandlerService.shared.handle(
                        error,
                        context: "CoachRemovalService.fetchFoldersForRevoke",
                        showAlert: false
                    )
                }
            }

            for folderID in folderIDs {
                await retryAsync {
                    try await FirestoreManager.shared.removeCoachFromFolder(
                        folderID: folderID,
                        coachID: coachID,
                        coachEmail: coachEmail
                    )
                }
            }
        }

        if let coachFirestoreID, let userID, let athleteFirestoreID {
            await retryAsync {
                try await FirestoreManager.shared.deleteCoach(
                    userId: userID,
                    athleteFirestoreId: athleteFirestoreID,
                    coachId: coachFirestoreID
                )
            }
        }
    }
}
