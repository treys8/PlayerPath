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
        coachFirestoreID: String?
    ) async {
        if let coachID = firebaseCoachID, !sharedFolderIDs.isEmpty {
            for folderID in sharedFolderIDs {
                await retryAsync {
                    try await FirestoreManager.shared.removeCoachFromFolder(
                        folderID: folderID,
                        coachID: coachID
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
