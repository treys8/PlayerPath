import Foundation
import SwiftData
import FirebaseAuth
import os

private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {

    // MARK: - Coaches Sync

    func syncCoaches(for user: User) async throws {
        guard let context = modelContext else { return }
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let athletes = user.athletes ?? []

        var syncedCoaches: [Coach] = []

        for athlete in athletes {
            guard let athleteFirestoreId = athlete.firestoreId else { continue }

            let coaches = athlete.coaches ?? []

            // Upload dirty coaches
            for coach in coaches where coach.needsSync {
                do {
                    if let coachFirestoreId = coach.firestoreId {
                        try await FirestoreManager.shared.updateCoach(
                            userId: userId,
                            athleteFirestoreId: athleteFirestoreId,
                            coachId: coachFirestoreId,
                            data: coach.toFirestoreData(athleteFirestoreId: athleteFirestoreId)
                        )
                    } else {
                        let docId = try await FirestoreManager.shared.createCoach(
                            userId: userId,
                            athleteFirestoreId: athleteFirestoreId,
                            data: coach.toFirestoreData(athleteFirestoreId: athleteFirestoreId)
                        )
                        coach.firestoreId = docId
                        // Save firestoreId immediately to prevent duplicate creation on crash
                        ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncCoaches.firestoreId")
                    }
                    coach.needsSync = false
                    syncedCoaches.append(coach)
                } catch {
                    syncLog.error("Failed to sync coach to Firestore: \(error.localizedDescription)")
                }
            }

            // Download / reconcile coaches.
            let remoteCoaches = try await FirestoreManager.shared.fetchCoaches(
                userId: userId,
                athleteFirestoreId: athleteFirestoreId
            )

            for remoteCoach in remoteCoaches {
                guard let remoteId = remoteCoach.id else { continue }

                // Match local by firestoreId first, then by stable secondary keys
                // (firebaseCoachID, case-insensitive email) so two devices that each
                // created the same coach converge instead of producing duplicates.
                let local = coaches.first { $0.firestoreId == remoteId }
                    ?? coaches.first { candidate in
                        guard candidate.firestoreId == nil else { return false }
                        if let fcid = remoteCoach.firebaseCoachID, candidate.firebaseCoachID == fcid {
                            return true
                        }
                        return !remoteCoach.email.isEmpty
                            && candidate.email.caseInsensitiveCompare(remoteCoach.email) == .orderedSame
                    }

                if let local {
                    // Adopt the remote firestoreId when matched via a secondary key.
                    if local.firestoreId == nil { local.firestoreId = remoteId }

                    // Field merge: absorb remote edits only when there's no pending
                    // local change (local-wins, mirroring the other entities). This
                    // is what surfaces an invitation accepted/declined on another
                    // device — e.g. lastInvitationStatus and firebaseCoachID — so the
                    // coach no longer shows "Not Connected" forever on this device.
                    if !local.needsSync {
                        let remotePhone = remoteCoach.phone ?? ""
                        let remoteNotes = remoteCoach.notes ?? ""
                        if local.name != remoteCoach.name { local.name = remoteCoach.name }
                        if local.role != remoteCoach.role { local.role = remoteCoach.role }
                        if local.email != remoteCoach.email { local.email = remoteCoach.email }
                        if local.phone != remotePhone { local.phone = remotePhone }
                        if local.notes != remoteNotes { local.notes = remoteNotes }
                        if local.firebaseCoachID != remoteCoach.firebaseCoachID {
                            local.firebaseCoachID = remoteCoach.firebaseCoachID
                        }
                        if local.lastInvitationStatus != remoteCoach.invitationStatus {
                            local.lastInvitationStatus = remoteCoach.invitationStatus
                        }
                    }
                } else {
                    let newCoach = Coach(
                        name: remoteCoach.name,
                        role: remoteCoach.role,
                        phone: remoteCoach.phone ?? "",
                        email: remoteCoach.email,
                        notes: remoteCoach.notes ?? ""
                    )
                    newCoach.createdAt = remoteCoach.createdAt
                    newCoach.firestoreId = remoteId
                    newCoach.needsSync = false
                    newCoach.firebaseCoachID = remoteCoach.firebaseCoachID
                    newCoach.lastInvitationStatus = remoteCoach.invitationStatus
                    newCoach.athlete = athlete
                    context.insert(newCoach)
                }
            }

            // Tombstone reconciliation — a previously-synced local coach absent from
            // the remote alive set was deleted on another device. fetchCoaches
            // already filters isDeleted == false, so a deleted coach simply won't
            // appear. Gated on connectivity (matches +HighlightReels): an offline
            // cached fetch must not drive destructive deletes. Skips dirty rows so a
            // pending local edit isn't lost.
            if ConnectivityMonitor.shared.isConnected {
                let remoteAliveIds = Set(remoteCoaches.compactMap { $0.id })
                for coach in coaches where !coach.needsSync {
                    guard let fid = coach.firestoreId, !remoteAliveIds.contains(fid) else { continue }
                    context.delete(coach)
                }
            }
        }

        // Save all changes to SwiftData — re-dirty on failure so next sync retries
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for coach in syncedCoaches { coach.needsSync = true }
                throw error
            }
        }
    }
}
