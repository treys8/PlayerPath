import Foundation
import SwiftData
import FirebaseAuth
import os

private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {
    // MARK: - Practices Sync (Phase 3)

    func syncPractices(for user: User) async throws {
        guard let context = modelContext else {
            return
        }


        do {
            // Step 1: Upload local changes to Firestore
            try await uploadLocalPractices(user, context: context)

            // Step 2: Download remote changes from Firestore
            try await downloadRemotePractices(user, context: context)

            // Step 3: Resolve conflicts (if any)
            try await resolvePracticeConflicts(user: user, context: context)


        } catch {
            appendSyncError(SyncError(
                type: .syncFailed,
                entityId: (user.firebaseAuthUid ?? user.id.uuidString),
                message: "Practice sync failed: \(error.localizedDescription)"
            ))
            throw error
        }
    }

    func uploadLocalPractices(_ user: User, context: ModelContext) async throws {
        let athletes = user.athletes ?? []
        var allPractices: [Practice] = []

        // Collect all practices from all athletes
        for athlete in athletes {
            let practices = athlete.practices ?? []
            allPractices.append(contentsOf: practices)
        }

        // Only upload practices whose parent athlete has already synced (has a firestoreId).
        let dirtyPractices = allPractices.filter { $0.needsSync && $0.athlete?.firestoreId != nil }

        guard !dirtyPractices.isEmpty else {
            return
        }

        var syncedPractices: [Practice] = []

        for practice in dirtyPractices {
            if practice.isDeletedRemotely {
                continue
            }

            do {
                if let firestoreId = practice.firestoreId {
                    // Update existing
                    try await FirestoreManager.shared.updatePractice(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        practiceId: firestoreId,
                        data: practice.toFirestoreData()
                    )
                } else {
                    // Create new
                    let docId = try await FirestoreManager.shared.createPractice(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        data: practice.toFirestoreData()
                    )
                    practice.firestoreId = docId
                    ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncPractices.firestoreId")
                }

                practice.needsSync = false
                practice.lastSyncDate = Date()
                practice.version += 1
                syncedPractices.append(practice)

            } catch {
                appendSyncError(SyncError(
                    type: .uploadFailed,
                    entityId: practice.id.uuidString,
                    message: "Practice upload failed: \(error.localizedDescription)"
                ))
            }
        }

        // Save all changes to SwiftData — re-dirty on failure so next sync retries
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for practice in syncedPractices { practice.needsSync = true }
                throw error
            }
        }
    }

    func downloadRemotePractices(_ user: User, context: ModelContext) async throws {

        let remotePractices = try await FirestoreManager.shared.fetchPractices(
            userId: (user.firebaseAuthUid ?? user.id.uuidString)
        )

        let athletes = user.athletes ?? []
        let remotePracticeIds = Set(remotePractices.compactMap { $0.id })

        // Detect practices deleted on another device — remote set no longer contains them.
        // Safety: skip bulk deletion if remote returned empty but local has synced practices,
        // which can happen on transient Firestore failures or network timeouts.
        for athlete in athletes {
            let syncedLocalPractices = (athlete.practices ?? []).filter { $0.firestoreId != nil }
            if !syncedLocalPractices.isEmpty && remotePracticeIds.isEmpty {
                syncLog.warning("Remote returned 0 practices but \(syncedLocalPractices.count) synced practices exist locally — skipping deletion pass to prevent data loss")
            } else {
                for localPractice in syncedLocalPractices {
                    if let firestoreId = localPractice.firestoreId, !remotePracticeIds.contains(firestoreId) {
                        localPractice.delete(in: context)
                    }
                }
            }
        }

        guard !remotePractices.isEmpty else {
            if context.hasChanges { try context.save() }
            return
        }

        for remoteData in remotePractices {
            // Find athlete by athleteId (matches local UUID or firestoreId).
            // Falls back to sole athlete for legacy data with stale local UUIDs.
            guard let athlete = athletes.first(where: {
                $0.id.uuidString == remoteData.athleteId || $0.firestoreId == remoteData.athleteId
            }) ?? (athletes.count == 1 ? athletes.first : nil) else {
                if athletes.count > 1 {
                    syncLog.error("Orphaned remote practice (athleteId=\(remoteData.athleteId)) — no matching local athlete among \(athletes.count) profiles.")
                }
                continue
            }

            // Find local practice by firestoreId
            let localPractice = (athlete.practices ?? []).first {
                $0.firestoreId == remoteData.id
            }

            if let local = localPractice {
                // Practice exists locally - check if remote is newer AND no pending local changes
                let remoteUpdatedAt = remoteData.updatedAt ?? Date.distantPast
                let localSyncDate = local.lastSyncDate ?? Date.distantPast

                if remoteUpdatedAt > localSyncDate && !local.needsSync {
                    local.date = remoteData.date
                    local.practiceType = remoteData.practiceType ?? local.practiceType
                    local.lastSyncDate = Date()
                    local.version = remoteData.version
                    local.needsSync = false
                }
            } else {
                // New practice from remote - create locally
                let newPractice = Practice(date: remoteData.date ?? Date.distantPast)
                newPractice.id = UUID(uuidString: remoteData.swiftDataId) ?? UUID()
                newPractice.firestoreId = remoteData.id
                newPractice.createdAt = remoteData.createdAt
                newPractice.lastSyncDate = Date()
                newPractice.needsSync = false
                newPractice.version = remoteData.version
                newPractice.practiceType = remoteData.practiceType ?? "general"
                newPractice.athlete = athlete

                // Link to season if seasonId provided
                if let seasonId = remoteData.seasonId {
                    if let season = athlete.seasons?.first(where: { $0.id.uuidString == seasonId || $0.firestoreId == seasonId }) {
                        newPractice.season = season
                    }
                }

                context.insert(newPractice)
            }
        }

        if context.hasChanges { try context.save() }
    }

    func resolvePracticeConflicts(user: User, context: ModelContext) async throws {
        // For now, local changes win (already marked needsSync)
    }
}
