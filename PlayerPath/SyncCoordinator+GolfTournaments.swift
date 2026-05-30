//
//  SyncCoordinator+GolfTournaments.swift
//  PlayerPath
//
//  Multi-round golf tournament sync (SchemaV27). Mirrors SyncCoordinator+Seasons:
//  a per-athlete top-level entity synced upload-dirty → download → reconcile,
//  with the destructive tombstone pass gated on connectivity.
//
//  Runs BEFORE Games in syncAll so the parent tournament exists locally when
//  downloadRemoteGames resolves a round's `tournamentId`. Deleting a tournament
//  is an UNLINK, never a cascade — its rounds survive as standalone rounds.
//

import Foundation
import SwiftData
import FirebaseAuth
import os

private let tournamentSyncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {

    /// Syncs all golf tournaments for a user bidirectionally (upload + download).
    func syncGolfTournaments(for user: User) async throws {
        guard let context = modelContext else { return }

        do {
            try await uploadLocalGolfTournaments(user, context: context)
            try await downloadRemoteGolfTournaments(user, context: context)
        } catch {
            appendSyncError(SyncError(
                type: .syncFailed,
                entityId: (user.firebaseAuthUid ?? user.id.uuidString),
                message: "Golf tournament sync failed: \(error.localizedDescription)"
            ))
            throw error
        }
    }

    func uploadLocalGolfTournaments(_ user: User, context: ModelContext) async throws {
        let athletes = user.athletes ?? []
        let allTournaments = athletes.flatMap { $0.golfTournaments ?? [] }
        // Only upload tournaments whose parent athlete has already synced, so we
        // never persist a local UUID as athleteId (would orphan on other devices).
        let dirty = allTournaments.filter { $0.needsSync && !$0.isDeletedRemotely && $0.athlete?.firestoreId != nil }

        guard !dirty.isEmpty else { return }

        var rollback: [(tournament: GolfTournament, needsSync: Bool, version: Int, lastSyncDate: Date?)] = []

        for tournament in dirty {
            let priorNeedsSync = tournament.needsSync
            let priorVersion = tournament.version
            let priorLastSync = tournament.lastSyncDate
            do {
                // Bump version BEFORE serialization so the written doc carries it.
                tournament.version += 1
                if let firestoreId = tournament.firestoreId {
                    try await FirestoreManager.shared.updateGolfTournament(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        tournamentId: firestoreId,
                        data: tournament.toFirestoreData()
                    )
                } else {
                    let docId = try await FirestoreManager.shared.createGolfTournament(
                        userId: (user.firebaseAuthUid ?? user.id.uuidString),
                        data: tournament.toFirestoreData()
                    )
                    tournament.firestoreId = docId
                    ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncGolfTournaments.firestoreId")
                }

                tournament.needsSync = false
                tournament.lastSyncDate = Date()
                rollback.append((tournament, priorNeedsSync, priorVersion, priorLastSync))
            } catch {
                tournament.version = priorVersion
                appendSyncError(SyncError(
                    type: .uploadFailed,
                    entityId: tournament.id.uuidString,
                    message: "Failed to upload tournament '\(tournament.name)': \(error.localizedDescription)"
                ))
            }
        }

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for entry in rollback {
                    entry.tournament.needsSync = true
                    entry.tournament.version = entry.version
                    entry.tournament.lastSyncDate = entry.lastSyncDate
                }
                throw error
            }
        }
    }

    func downloadRemoteGolfTournaments(_ user: User, context: ModelContext) async throws {
        let remoteTournaments = try await FirestoreManager.shared.fetchGolfTournaments(
            userId: (user.firebaseAuthUid ?? user.id.uuidString)
        )

        let athletes = user.athletes ?? []
        let allLocal = athletes.flatMap { $0.golfTournaments ?? [] }

        // Tombstone reconciliation — a synced local tournament absent from the
        // remote alive set was deleted on another device. UNLINK its rounds
        // (they survive as standalone rounds) and re-dirty them so the cleared
        // tournamentId re-syncs, then delete the tournament. Gated on
        // connectivity: an offline cached fetch can return a stale/empty set
        // without throwing — never delete on non-authoritative data.
        let remoteIds = Set(remoteTournaments.compactMap { $0.id })
        let syncedLocal = allLocal.filter { $0.firestoreId != nil }
        if ConnectivityMonitor.shared.isConnected {
            for local in syncedLocal {
                guard let fsId = local.firestoreId, !remoteIds.contains(fsId) else { continue }
                for round in local.rounds ?? [] {
                    round.tournament = nil
                    round.roundNumber = nil
                    round.needsSync = true
                }
                local.rounds = nil
                context.delete(local)
            }
        } else {
            tournamentSyncLog.warning("Skipping golf tournament deletion pass — offline (would risk wiping synced tournaments)")
        }

        for remote in remoteTournaments {
            let local = allLocal.first { $0.firestoreId == remote.id }

            // Find parent athlete by athleteId (firestoreId or local UUID), with
            // the sole-athlete fallback for legacy stale-UUID data.
            let parentAthlete: Athlete? = athletes.first {
                $0.id.uuidString == remote.athleteId || $0.firestoreId == remote.athleteId
            } ?? (athletes.count == 1 ? athletes.first : nil)

            if parentAthlete == nil && athletes.count > 1 {
                tournamentSyncLog.error("Orphaned remote tournament '\(remote.name)' (athleteId=\(remote.athleteId)) — no matching local athlete among \(athletes.count) profiles.")
            }

            if let local = local {
                let remoteIsNewer = (remote.updatedAt ?? Date.distantPast) > (local.lastSyncDate ?? Date.distantPast)

                if remoteIsNewer && local.needsSync {
                    tournamentSyncLog.warning("Sync conflict on tournament '\(local.name)': local has pending changes, skipping remote update")
                    appendSyncError(SyncError(
                        type: .conflictResolution,
                        entityId: local.id.uuidString,
                        message: "Tournament '\(local.name)' modified on both devices — local changes kept"
                    ))
                } else if remoteIsNewer {
                    var changed = false
                    if local.name != remote.name { local.name = remote.name; changed = true }
                    if local.location != remote.location { local.location = remote.location; changed = true }
                    if local.startDate != remote.startDate { local.startDate = remote.startDate; changed = true }
                    if local.endDate != remote.endDate { local.endDate = remote.endDate; changed = true }
                    if local.notes != remote.notes { local.notes = remote.notes; changed = true }
                    if local.version != remote.version { local.version = remote.version; changed = true }
                    if changed {
                        local.lastSyncDate = remote.updatedAt ?? Date()
                    }
                }
            } else if let athlete = parentAthlete {
                let newTournament = GolfTournament(name: remote.name, startDate: remote.startDate)
                newTournament.id = UUID(uuidString: remote.swiftDataId) ?? UUID()
                newTournament.firestoreId = remote.id
                newTournament.location = remote.location
                newTournament.endDate = remote.endDate
                newTournament.notes = remote.notes
                newTournament.createdAt = remote.createdAt
                newTournament.lastSyncDate = Date()
                newTournament.needsSync = false
                newTournament.version = remote.version
                newTournament.athlete = athlete
                context.insert(newTournament)
            } else {
                tournamentSyncLog.warning("Dropped remote tournament '\(remote.name)' (id: \(remote.id ?? "nil")) — no matching athlete for athleteId '\(remote.athleteId)'")
            }
        }

        if context.hasChanges { try context.save() }
    }
}
