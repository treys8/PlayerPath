//
//  Athlete.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import Foundation
import SwiftData

enum AthleteRole: String, Codable, CaseIterable {
    case batter
    case pitcher
    case both

    var displayName: String {
        switch self {
        case .batter: return "Batter"
        case .pitcher: return "Pitcher"
        case .both: return "Both"
        }
    }
}

@Model
final class Athlete {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date?
    var user: User?
    var primaryRole: AthleteRole = AthleteRole.batter
    @Relationship(inverse: \Season.athlete) var seasons: [Season]?
    @Relationship(inverse: \Game.athlete) var games: [Game]?
    @Relationship(inverse: \Practice.athlete) var practices: [Practice]?
    @Relationship(inverse: \VideoClip.athlete) var videoClips: [VideoClip]?
    @Relationship(inverse: \AthleteStatistics.athlete) var statistics: AthleteStatistics?
    @Relationship(inverse: \Coach.athlete) var coaches: [Coach]?
    @Relationship(inverse: \Photo.athlete) var photos: [Photo]?

    // MARK: - Firestore Sync Metadata
    var firestoreId: String?        // Maps to Firestore document ID
    var lastSyncDate: Date?         // Last successful sync timestamp
    var needsSync: Bool = false     // Dirty flag - needs upload to Firestore
    var isDeletedRemotely: Bool = false  // Soft delete from another device
    var version: Int = 0            // Version number for conflict resolution

    /// When false, new clips save without the play-result tagging prompt and the
    /// Stats tab shows a disabled-tracking banner. Existing tagged clips remain
    /// and their stats stay visible. Defaults to true so existing athletes keep
    /// their current behavior after migration.
    var trackStatsEnabled: Bool = true

    /// The currently active season for this athlete (only one can be active at a time)
    var activeSeason: Season? {
        seasons?.first(where: { $0.isActive })
    }

    /// All archived (completed) seasons, sorted by start date descending
    var archivedSeasons: [Season] {
        (seasons ?? [])
            .filter { !$0.isActive }
            .sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    // MARK: - Deep Deletion

    /// Properly delete athlete with all associated files and data.
    /// Use this instead of modelContext.delete(athlete) to avoid orphaning children.
    @MainActor func delete(in context: ModelContext) {
        // Cancel any pending uploads for this athlete before deleting clips
        let athleteId = id
        Task { @MainActor in
            UploadQueueManager.shared.cancelUploads(forAthleteId: athleteId)
        }

        // Track which clips are owned by a game or practice so we don't double-delete
        var deletedClipIDs = Set<UUID>()

        // Delete all games (and their video clips, stats)
        for game in games ?? [] {
            for clip in game.videoClips ?? [] {
                clip.delete(in: context)
                deletedClipIDs.insert(clip.id)
            }
            if let gameStats = game.gameStats {
                context.delete(gameStats)
            }
            context.delete(game)
        }

        // Delete all practices (and their video clips, notes)
        for practice in practices ?? [] {
            for clip in practice.videoClips ?? [] where !deletedClipIDs.contains(clip.id) {
                clip.delete(in: context)
                deletedClipIDs.insert(clip.id)
            }
            for note in practice.notes ?? [] {
                context.delete(note)
            }
            context.delete(practice)
        }

        // Delete remaining standalone video clips (not attached to a game or practice)
        for clip in videoClips ?? [] where !deletedClipIDs.contains(clip.id) {
            clip.delete(in: context)
        }

        // Delete all photos (handles local files and cloud)
        for photo in photos ?? [] {
            photo.delete(in: context)
        }

        // Delete seasons and their statistics
        for season in seasons ?? [] {
            if let seasonStats = season.seasonStatistics {
                context.delete(seasonStats)
            }
            context.delete(season)
        }

        // Delete coaches
        for coach in coaches ?? [] {
            context.delete(coach)
        }

        // Delete athlete statistics
        if let stats = statistics {
            context.delete(stats)
        }

        context.delete(self)
    }

    // MARK: - Firestore Conversion
    func toFirestoreData() -> [String: Any] {
        return [
            "id": id.uuidString,
            "name": name,
            "userId": user?.id.uuidString ?? "",
            "primaryRole": primaryRole.rawValue,
            "trackStatsEnabled": trackStatsEnabled,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]
    }
}
