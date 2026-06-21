//
//  SyncCoordinator+Shots.swift
//  PlayerPath
//
//  Per-shot golf sync (SchemaV30). Mirrors +HoleScores, with two deliberate
//  differences:
//    • Nested one level deeper — iterate rounds → holes → shots.
//    • Reconcile keys on the shot UUID (NOT a positional number), because shots
//      reorder on delete/insert. A holeNumber-style positional reconcile would
//      overwrite the wrong shot and break cross-device delete/insert.
//
//  Only rounds with `tracksShotByShot == true` are touched, so casual golf and
//  baseball rounds incur zero shot reads. Runs AFTER HoleScores in the
//  orchestrator so the parent hole docs already exist.
//

import Foundation
import SwiftData
import FirebaseAuth
import os

private let shotSyncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {

    func syncShots(for user: User) async throws {
        guard let context = modelContext else { return }
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let athletes = user.athletes ?? []
        let golfGames = athletes
            .flatMap { $0.games ?? [] }
            .filter { $0.season?.sport == .golf && $0.tracksShotByShot }
        let practiceRounds = athletes
            .flatMap { $0.practices ?? [] }
            .filter { $0.practiceType == "practice_round" && $0.tracksShotByShot }

        var syncedShots: [Shot] = []

        for game in golfGames {
            guard let gameFirestoreId = game.firestoreId else { continue }
            for hole in (game.holeScores ?? []) {
                // Upload dirty shots first so a timeout (e.g. sign-out flush)
                // never loses an unsynced shot.
                for shot in (hole.shots ?? []).filter({ $0.needsSync }) {
                    do {
                        if shot.isDeletedRemotely {
                            // Locally deleted after it had synced — tombstone the
                            // remote doc, then drop the local row. (Durable: if
                            // offline this stays dirty and retries next pass.)
                            try await FirestoreManager.shared.deleteGameShot(
                                userId: userId, gameFirestoreId: gameFirestoreId,
                                holeNumber: hole.holeNumber, shotId: shot.id.uuidString)
                            context.delete(shot)
                            continue
                        }
                        if shot.firestoreId == nil {
                            try await FirestoreManager.shared.createGameShot(
                                userId: userId, gameFirestoreId: gameFirestoreId,
                                holeNumber: hole.holeNumber, shotId: shot.id.uuidString,
                                data: shot.toFirestoreData())
                            shot.firestoreId = shot.id.uuidString
                        } else {
                            try await FirestoreManager.shared.updateGameShot(
                                userId: userId, gameFirestoreId: gameFirestoreId,
                                holeNumber: hole.holeNumber, shotId: shot.id.uuidString,
                                data: shot.toFirestoreData())
                        }
                        shot.needsSync = false
                        shot.lastSyncDate = Date()
                        syncedShots.append(shot)
                    } catch {
                        shotSyncLog.error("Failed to sync Shot (game) hole=\(hole.holeNumber) shot=\(shot.shotNumber): \(error.localizedDescription)")
                    }
                }

                let remoteShots = try await FirestoreManager.shared.fetchGameShots(
                    userId: userId, gameFirestoreId: gameFirestoreId, holeNumber: hole.holeNumber)
                reconcileShots(remoteShots: remoteShots, localShots: hole.shots ?? [],
                               attach: { $0.holeScore = hole }, in: context)
            }
        }

        for practice in practiceRounds {
            guard let practiceFirestoreId = practice.firestoreId else { continue }
            for hole in (practice.holeScores ?? []) {
                for shot in (hole.shots ?? []).filter({ $0.needsSync }) {
                    do {
                        if shot.isDeletedRemotely {
                            try await FirestoreManager.shared.deletePracticeShot(
                                userId: userId, practiceFirestoreId: practiceFirestoreId,
                                holeNumber: hole.holeNumber, shotId: shot.id.uuidString)
                            context.delete(shot)
                            continue
                        }
                        if shot.firestoreId == nil {
                            try await FirestoreManager.shared.createPracticeShot(
                                userId: userId, practiceFirestoreId: practiceFirestoreId,
                                holeNumber: hole.holeNumber, shotId: shot.id.uuidString,
                                data: shot.toFirestoreData())
                            shot.firestoreId = shot.id.uuidString
                        } else {
                            try await FirestoreManager.shared.updatePracticeShot(
                                userId: userId, practiceFirestoreId: practiceFirestoreId,
                                holeNumber: hole.holeNumber, shotId: shot.id.uuidString,
                                data: shot.toFirestoreData())
                        }
                        shot.needsSync = false
                        shot.lastSyncDate = Date()
                        syncedShots.append(shot)
                    } catch {
                        shotSyncLog.error("Failed to sync Shot (practice) hole=\(hole.holeNumber) shot=\(shot.shotNumber): \(error.localizedDescription)")
                    }
                }

                let remoteShots = try await FirestoreManager.shared.fetchPracticeShots(
                    userId: userId, practiceFirestoreId: practiceFirestoreId, holeNumber: hole.holeNumber)
                reconcileShots(remoteShots: remoteShots, localShots: hole.shots ?? [],
                               attach: { $0.holeScore = hole }, in: context)
            }
        }

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for shot in syncedShots { shot.needsSync = true }
                throw error
            }
        }
    }

    /// Reconciles a hole's local shots against the remote alive set, keyed on
    /// the shot UUID:
    ///   • inserts remote shots missing locally,
    ///   • mirrors remote edits onto existing non-dirty local shots when the
    ///     remote is newer (version, then `updatedAt`), and
    ///   • deletes previously-synced local shots vanished from the remote alive
    ///     set (deleted on another device).
    ///
    /// Only ever called after a successful fetch, so a network error can't wipe
    /// local shots.
    private func reconcileShots(
        remoteShots: [FirestoreShot],
        localShots: [Shot],
        attach: (Shot) -> Void,
        in context: ModelContext
    ) {
        let localByID = Dictionary(
            localShots.map { ($0.id.uuidString, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let remoteAliveIDs = Set(remoteShots.compactMap(\.id))

        for remote in remoteShots {
            guard let remoteID = remote.id else { continue }
            if let local = localByID[remoteID] {
                guard !local.needsSync else { continue }
                let remoteVersion = remote.version ?? 0
                let isNewer = remoteVersion > local.version ||
                    (remoteVersion == local.version &&
                     (remote.updatedAt ?? .distantPast) > (local.updatedAt ?? .distantPast))
                if isNewer {
                    local.shotNumber = remote.shotNumber
                    local.clubRaw = remote.club
                    local.lieRaw = remote.lie
                    local.outcomeRaw = remote.outcome
                    local.penaltyStrokes = remote.penaltyStrokes
                    local.distanceBefore = remote.distanceBefore
                    local.isPutt = remote.isPutt
                    local.version = remoteVersion
                    local.updatedAt = remote.updatedAt
                    local.lastSyncDate = Date()
                }
            } else {
                let local = Shot(
                    shotNumber: remote.shotNumber,
                    club: remote.club.flatMap(Club.init(rawValue:)),
                    lie: ShotLie(rawValue: remote.lie) ?? .tee,
                    outcome: ShotOutcome(rawValue: remote.outcome) ?? .fairway,
                    penaltyStrokes: remote.penaltyStrokes,
                    distanceBefore: remote.distanceBefore,
                    isPutt: remote.isPutt
                )
                // Preserve the remote UUID so this row reconciles by id on every
                // device — a fresh UUID would re-insert it as a duplicate.
                local.id = UUID(uuidString: remoteID) ?? local.id
                local.createdAt = remote.createdAt
                local.updatedAt = remote.updatedAt
                local.firestoreId = remoteID
                local.version = remote.version ?? 0
                local.needsSync = false
                local.lastSyncDate = Date()
                attach(local)
                context.insert(local)
            }
        }

        // Tombstone reconciliation — gated on connectivity (offline getDocuments
        // can return a stale/empty set without throwing; a destructive delete
        // must only act on authoritative online data).
        guard ConnectivityMonitor.shared.isConnected else { return }
        for local in localShots
        where local.firestoreId != nil && !local.needsSync && !remoteAliveIDs.contains(local.id.uuidString) {
            context.delete(local)
        }
    }
}
