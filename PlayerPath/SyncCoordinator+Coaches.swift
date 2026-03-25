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

            // Download coaches that exist remotely but not locally
            let remoteCoaches = try await FirestoreManager.shared.fetchCoaches(
                userId: userId,
                athleteFirestoreId: athleteFirestoreId
            )
            let localCoachIds = Set(coaches.compactMap { $0.firestoreId })
            for remoteCoach in remoteCoaches where !localCoachIds.contains(remoteCoach.id ?? "") {
                let newCoach = Coach(
                    name: remoteCoach.name,
                    role: remoteCoach.role,
                    phone: remoteCoach.phone ?? "",
                    email: remoteCoach.email,
                    notes: remoteCoach.notes ?? ""
                )
                newCoach.createdAt = remoteCoach.createdAt
                newCoach.firestoreId = remoteCoach.id
                newCoach.needsSync = false
                newCoach.firebaseCoachID = remoteCoach.firebaseCoachID
                newCoach.lastInvitationStatus = remoteCoach.invitationStatus
                newCoach.athlete = athlete
                context.insert(newCoach)
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
