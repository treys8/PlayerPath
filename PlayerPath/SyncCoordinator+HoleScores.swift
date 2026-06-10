//
//  SyncCoordinator+HoleScores.swift
//  PlayerPath
//
//  Per-hole golf scoring sync (SchemaV25). Mirrors the +PracticeNotes pattern:
//  iterate the parent entities, upload dirty rows, then pull missing remote
//  rows. Keyed by (parent, holeNumber) — the Firestore doc id is the hole
//  number string, so re-scoring is an upsert rather than a duplicate.
//
//  Practice-round sync is active (PR3): hole rows are synced for practices
//  whose `practiceType == "practice_round"`; range sessions and baseball
//  practices carry no hole rows.
//

import Foundation
import SwiftData
import FirebaseAuth
import os

private let holeSyncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {

    func syncHoleScores(for user: User) async throws {
        guard let context = modelContext else { return }
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let athletes = user.athletes ?? []
        let golfGames = athletes
            .flatMap { $0.games ?? [] }
            .filter { $0.season?.sport == .golf }
        let practiceRounds = athletes
            .flatMap { $0.practices ?? [] }
            .filter { $0.practiceType == "practice_round" }

        var syncedHoles: [HoleScore] = []

        for game in golfGames {
            guard let gameFirestoreId = game.firestoreId else { continue }

            // Upload dirty per-hole rows
            let dirtyHoles = (game.holeScores ?? []).filter { $0.needsSync }
            for hole in dirtyHoles {
                do {
                    if hole.firestoreId == nil {
                        try await FirestoreManager.shared.createGameHoleScore(
                            userId: userId,
                            gameFirestoreId: gameFirestoreId,
                            holeNumber: hole.holeNumber,
                            data: hole.toFirestoreData()
                        )
                        hole.firestoreId = String(hole.holeNumber)
                    } else {
                        try await FirestoreManager.shared.updateGameHoleScore(
                            userId: userId,
                            gameFirestoreId: gameFirestoreId,
                            holeNumber: hole.holeNumber,
                            data: hole.toFirestoreData()
                        )
                    }
                    hole.needsSync = false
                    hole.lastSyncDate = Date()
                    syncedHoles.append(hole)
                } catch {
                    holeSyncLog.error("Failed to sync HoleScore (game) hole=\(hole.holeNumber): \(error.localizedDescription)")
                }
            }

            // Download remote rows, absorb remote edits, and reconcile tombstones.
            let remoteHoles = try await FirestoreManager.shared.fetchGameHoleScores(
                userId: userId,
                gameFirestoreId: gameFirestoreId
            )
            reconcileHoles(
                remoteHoles: remoteHoles,
                localHoles: game.holeScores ?? [],
                attach: { $0.game = game },
                in: context
            )
        }

        for practice in practiceRounds {
            guard let practiceFirestoreId = practice.firestoreId else { continue }

            let dirtyHoles = (practice.holeScores ?? []).filter { $0.needsSync }
            for hole in dirtyHoles {
                do {
                    if hole.firestoreId == nil {
                        try await FirestoreManager.shared.createPracticeHoleScore(
                            userId: userId,
                            practiceFirestoreId: practiceFirestoreId,
                            holeNumber: hole.holeNumber,
                            data: hole.toFirestoreData()
                        )
                        hole.firestoreId = String(hole.holeNumber)
                    } else {
                        try await FirestoreManager.shared.updatePracticeHoleScore(
                            userId: userId,
                            practiceFirestoreId: practiceFirestoreId,
                            holeNumber: hole.holeNumber,
                            data: hole.toFirestoreData()
                        )
                    }
                    hole.needsSync = false
                    hole.lastSyncDate = Date()
                    syncedHoles.append(hole)
                } catch {
                    holeSyncLog.error("Failed to sync HoleScore (practice) hole=\(hole.holeNumber): \(error.localizedDescription)")
                }
            }

            let remoteHoles = try await FirestoreManager.shared.fetchPracticeHoleScores(
                userId: userId,
                practiceFirestoreId: practiceFirestoreId
            )
            reconcileHoles(
                remoteHoles: remoteHoles,
                localHoles: practice.holeScores ?? [],
                attach: { $0.practice = practice },
                in: context
            )
        }

        // Save all changes — re-dirty on failure so the next pass retries.
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for hole in syncedHoles { hole.needsSync = true }
                throw error
            }
        }
    }

    /// Reconciles a parent's local holes against the remote alive set:
    ///   • inserts remote rows missing locally,
    ///   • mirrors remote edits onto existing non-dirty local rows when the
    ///     remote is newer (version, then `updatedAt`), and
    ///   • deletes previously-synced local rows that have vanished from the
    ///     remote alive set (soft-deleted on another device).
    ///
    /// Only ever called after a successful fetch — a throwing fetch skips the
    /// whole block, so a network error can't wipe local rows.
    private func reconcileHoles(
        remoteHoles: [FirestoreHoleScore],
        localHoles: [HoleScore],
        attach: (HoleScore) -> Void,
        in context: ModelContext
    ) {
        let localByNumber = Dictionary(
            localHoles.map { ($0.holeNumber, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let remoteAliveNumbers = Set(remoteHoles.map(\.holeNumber))

        for remote in remoteHoles {
            if let local = localByNumber[remote.holeNumber] {
                // Existing local row — absorb remote edits only when we have no
                // pending local change and the remote is strictly newer.
                guard !local.needsSync else { continue }
                let remoteVersion = remote.version ?? 0
                let isNewer = remoteVersion > local.version ||
                    (remoteVersion == local.version &&
                     (remote.updatedAt ?? .distantPast) > (local.updatedAt ?? .distantPast))
                if isNewer {
                    local.par = remote.par
                    local.score = remote.score
                    local.putts = remote.putts
                    local.fairwayHit = remote.fairwayHit
                    local.greenInRegulation = remote.greenInRegulation
                    local.penalties = remote.penalties
                    local.version = remoteVersion
                    local.updatedAt = remote.updatedAt
                    local.lastSyncDate = Date()
                }
            } else {
                let local = HoleScore(
                    holeNumber: remote.holeNumber,
                    par: remote.par,
                    score: remote.score,
                    putts: remote.putts,
                    fairwayHit: remote.fairwayHit,
                    greenInRegulation: remote.greenInRegulation,
                    penalties: remote.penalties
                )
                local.createdAt = remote.createdAt
                local.updatedAt = remote.updatedAt
                local.firestoreId = remote.id
                local.version = remote.version ?? 0
                local.needsSync = false
                local.lastSyncDate = Date()
                attach(local)
                context.insert(local)
            }
        }

        // Tombstone reconciliation — a synced local hole absent from the remote
        // alive set was soft-deleted elsewhere. Gated on connectivity: Firestore
        // persistent cache is enabled, so an OFFLINE getDocuments can return a
        // stale/empty set without throwing. Inserts/merges above are harmless in
        // that case, but a destructive delete must only act on authoritative
        // (online) server data.
        guard ConnectivityMonitor.shared.isConnected else { return }
        for local in localHoles
        where local.firestoreId != nil && !local.needsSync && !remoteAliveNumbers.contains(local.holeNumber) {
            context.delete(local)
        }
    }
}
