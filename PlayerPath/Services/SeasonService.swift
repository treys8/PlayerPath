//
//  SeasonService.swift
//  PlayerPath
//
//  Centralizes season mutations (end, reactivate, delete, rename) with their
//  rollback and Firestore sync, so views don't duplicate the pattern.
//

import Foundation
import SwiftData
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "SeasonService")

@MainActor
struct SeasonService {

    enum SeasonServiceError: LocalizedError {
        case firestoreDeleteFailed
        case localSaveAfterFirestoreDelete
        case saveFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .firestoreDeleteFailed:
                return "Unable to delete season. Check your connection and try again."
            case .localSaveAfterFirestoreDelete:
                return "Deleted from cloud but local cleanup didn't finish. It'll clear on the next sync."
            case .saveFailed(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    /// Archives the season and aggregates its stats. Saves context and triggers Firestore sync.
    /// Rolls back local mutations if the save fails.
    static func endSeason(_ season: Season, modelContext: ModelContext) async throws {
        let wasActive = season.isActive
        let previousEndDate = season.endDate

        season.archive()
        season.needsSync = true

        do {
            try modelContext.save()
        } catch {
            if wasActive { season.activate() }
            season.endDate = previousEndDate
            throw SeasonServiceError.saveFailed(underlying: error)
        }

        let gameCount = season.games?.count ?? 0
        AnalyticsService.shared.trackSeasonEnded(
            seasonID: season.id.uuidString,
            totalGames: gameCount
        )

        if let user = season.athlete?.user {
            do {
                try await SyncCoordinator.shared.syncSeasons(for: user)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "SeasonService.endSeason.syncSeasons", showAlert: false)
            }
        }
    }

    /// Reactivates an archived season. Archives the previously-active season for the same athlete (if any).
    /// Rolls back local mutations if the save fails.
    static func reactivateSeason(_ season: Season, athlete: Athlete, modelContext: ModelContext) async throws {
        let previousActive = athlete.activeSeason
        let previousActiveWasActive = previousActive?.isActive ?? false
        let previousActiveEndDate = previousActive?.endDate
        let wasActive = season.isActive
        let previousEndDate = season.endDate

        previousActive?.archive()
        season.activate()

        season.needsSync = true
        previousActive?.needsSync = true

        do {
            try modelContext.save()
        } catch {
            if previousActiveWasActive {
                previousActive?.activate()
                previousActive?.endDate = previousActiveEndDate
            }
            if !wasActive {
                season.isActive = false
            }
            season.endDate = previousEndDate
            throw SeasonServiceError.saveFailed(underlying: error)
        }

        AnalyticsService.shared.trackSeasonActivated(seasonID: season.id.uuidString)

        if let user = season.athlete?.user {
            do {
                try await SyncCoordinator.shared.syncSeasons(for: user)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "SeasonService.reactivateSeason.syncSeasons", showAlert: false)
            }
        }
    }

    /// Firestore-first delete. Marks attached games/practices/videos dirty before delinking
    /// so the next sync clears their stale `seasonId` server-side. The user's intent (per the
    /// confirmation alert) is to keep the children but un-associate them from a season.
    static func deleteSeason(_ season: Season, modelContext: ModelContext) async throws {
        if let firestoreId = season.firestoreId,
           let user = season.athlete?.user {
            let userId = user.id.uuidString
            do {
                try await withRetry {
                    try await FirestoreManager.shared.deleteSeason(userId: userId, seasonId: firestoreId)
                }
            } catch {
                ErrorHandlerService.shared.handle(error, context: "SeasonService.deleteSeason.firestore", showAlert: false)
                throw SeasonServiceError.firestoreDeleteFailed
            }
        }

        // Mark children dirty so the seasonId clearing re-syncs to Firestore.
        for game in season.games ?? [] { game.needsSync = true }
        for practice in season.practices ?? [] { practice.needsSync = true }
        for clip in season.videoClips ?? [] { clip.needsSync = true }

        // Delink so SwiftData cascade doesn't sweep the children.
        season.games = nil
        season.practices = nil
        season.videoClips = nil

        modelContext.delete(season)

        do {
            try modelContext.save()
        } catch {
            // Firestore is already deleted and is the source of truth — don't re-insert.
            ErrorHandlerService.shared.handle(
                error,
                context: "SeasonService.deleteSeason.localSave",
                showAlert: false
            )
            throw SeasonServiceError.localSaveAfterFirestoreDelete
        }

        if let user = season.athlete?.user {
            do {
                try await SyncCoordinator.shared.syncSeasons(for: user)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "SeasonService.deleteSeason.syncSeasons", showAlert: false)
            }
            do {
                try await SyncCoordinator.shared.syncGames(for: user)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "SeasonService.deleteSeason.syncGames", showAlert: false)
            }
            do {
                try await SyncCoordinator.shared.syncPractices(for: user)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "SeasonService.deleteSeason.syncPractices", showAlert: false)
            }
            do {
                try await SyncCoordinator.shared.syncVideos(for: user)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "SeasonService.deleteSeason.syncVideos", showAlert: false)
            }
        }
    }

    /// Renames the season and propagates the new display name onto every attached VideoClip.
    /// Rolls back local mutations if the save fails.
    static func renameSeason(_ season: Season, to newName: String, modelContext: ModelContext) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != season.name else { return }

        let oldName = season.name
        let oldClipSeasonNames: [(VideoClip, String)] = (season.videoClips ?? []).map { ($0, $0.seasonName ?? "") }

        season.name = trimmed
        season.needsSync = true

        for clip in season.videoClips ?? [] {
            clip.seasonName = season.displayName
            if clip.firestoreId != nil {
                clip.needsSync = true
            }
        }

        do {
            try modelContext.save()
        } catch {
            season.name = oldName
            for (clip, oldSeasonName) in oldClipSeasonNames {
                clip.seasonName = oldSeasonName
            }
            throw SeasonServiceError.saveFailed(underlying: error)
        }

        if let user = season.athlete?.user {
            do {
                try await SyncCoordinator.shared.syncSeasons(for: user)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "SeasonService.renameSeason.syncSeasons", showAlert: false)
            }
            do {
                try await SyncCoordinator.shared.syncVideos(for: user)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "SeasonService.renameSeason.syncVideos", showAlert: false)
            }
        }
    }
}
