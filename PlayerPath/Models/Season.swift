//
//  Season.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Season {
    var id: UUID = UUID()
    var name: String = ""
    var startDate: Date?
    var endDate: Date?
    var isActive: Bool = false
    var createdAt: Date?
    var athlete: Athlete?
    @Relationship(inverse: \Game.season) var games: [Game]?
    @Relationship(inverse: \Practice.season) var practices: [Practice]?
    @Relationship(inverse: \VideoClip.season) var videoClips: [VideoClip]?
    @Relationship(inverse: \Photo.season) var photos: [Photo]?

    /// Season-specific statistics (initialized at creation, updated as games are played)
    @Relationship(inverse: \AthleteStatistics.season) var seasonStatistics: AthleteStatistics?

    /// Notes about the season (goals, achievements, etc.)
    var notes: String = ""

    /// Sport for this season (baseball or softball)
    var sport: SportType = SportType.baseball

    // MARK: - Firestore Sync Metadata (Phase 2)

    /// Firestore document ID (maps to cloud storage)
    var firestoreId: String?

    /// Last successful sync timestamp
    var lastSyncDate: Date?

    /// Dirty flag - true when local changes need uploading
    var needsSync: Bool = false

    /// Soft delete flag - true when deleted on another device
    var isDeletedRemotely: Bool = false

    /// Version number for conflict resolution
    var version: Int = 0

    /// Computed sync status
    var isSynced: Bool {
        needsSync == false && firestoreId != nil
    }

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()
    private static let yearPattern: NSRegularExpression? = try? NSRegularExpression(pattern: #"\b\d{4}\b"#)

    /// Computed display name with year range
    var displayName: String {
        // If name already contains a year (4 digits), just return it
        let range = NSRange(name.startIndex..., in: name)
        if let pattern = Self.yearPattern, pattern.firstMatch(in: name, range: range) != nil {
            return name
        }

        // Otherwise, append year from dates
        if let start = startDate, let end = endDate {
            let startYear = Self.yearFormatter.string(from: start)
            let endYear = Self.yearFormatter.string(from: end)

            if startYear == endYear {
                return "\(name) \(startYear)"
            } else {
                return "\(name) \(startYear)-\(endYear)"
            }
        } else if let start = startDate {
            return "\(name) \(Self.yearFormatter.string(from: start))"
        }
        return name
    }

    /// Is this season archived (ended)?
    var isArchived: Bool {
        return !isActive && endDate != nil
    }

    /// Current status of the season
    var status: SeasonStatus {
        if isActive {
            return .active
        } else if isArchived {
            return .ended
        } else {
            return .inactive
        }
    }

    enum SeasonStatus: String {
        case active = "Active"
        case ended = "Ended"
        case inactive = "Inactive"

        var displayName: String { rawValue }

        var color: String {
            switch self {
            case .active: return "blue"
            case .ended: return "gray"
            case .inactive: return "orange"
            }
        }

        var icon: String {
            switch self {
            case .active: return "calendar.circle.fill"
            case .ended: return "calendar.badge.checkmark"
            case .inactive: return "calendar"
            }
        }
    }

    /// Total number of games played in this season
    var totalGames: Int {
        (games ?? []).filter { $0.isComplete }.count
    }

    /// Total videos recorded during this season
    var totalVideos: Int {
        (videoClips ?? []).count
    }

    /// All highlight videos from this season
    var highlights: [VideoClip] {
        (videoClips ?? []).filter { $0.isHighlight }
    }

    enum SportType: String, Codable, CaseIterable {
        case baseball = "Baseball"
        case softball = "Softball"

        var displayName: String { rawValue }

        var icon: String {
            switch self {
            case .baseball: return "figure.baseball"
            case .softball: return "figure.softball"
            }
        }
    }

    init(name: String, startDate: Date, sport: SportType = .baseball) {
        self.id = UUID()
        self.name = name
        self.startDate = startDate
        self.sport = sport
        self.isActive = false
        self.createdAt = Date()

        // Initialize empty statistics so season comparisons work immediately
        let stats = AthleteStatistics()
        stats.season = self
        self.seasonStatistics = stats
    }

    /// End this season and archive it
    func archive(endDate: Date? = nil) {
        self.endDate = endDate ?? Date()
        self.isActive = false

        // Calculate and save season statistics
        let stats = seasonStatistics ?? AthleteStatistics()
        if seasonStatistics == nil {
            seasonStatistics = stats
        }

        // Reset before aggregating so re-archiving doesn't double-count
        stats.singles = 0
        stats.doubles = 0
        stats.triples = 0
        stats.homeRuns = 0
        stats.runs = 0
        stats.rbis = 0
        stats.walks = 0
        stats.strikeouts = 0
        stats.atBats = 0
        stats.hits = 0
        stats.hitByPitches = 0

        // Aggregate all game stats into season stats
        for game in (games ?? []) where game.isComplete {
            if let gameStats = game.gameStats {
                stats.singles += gameStats.singles
                stats.doubles += gameStats.doubles
                stats.triples += gameStats.triples
                stats.homeRuns += gameStats.homeRuns
                stats.runs += gameStats.runs
                stats.rbis += gameStats.rbis
                stats.walks += gameStats.walks
                stats.strikeouts += gameStats.strikeouts
                stats.atBats += gameStats.atBats
                stats.hits += gameStats.hits
                stats.hitByPitches += gameStats.hitByPitches
            }
        }

        stats.totalGames = totalGames
        stats.updatedAt = Date()
    }

    /// Activate this season (deactivates other seasons for this athlete)
    func activate() {
        // Deactivate all other seasons for this athlete and stamp their end date
        if let athlete = self.athlete {
            for season in (athlete.seasons ?? []) where season.id != self.id {
                if season.isActive && season.endDate == nil {
                    season.endDate = Date()
                }
                season.isActive = false
            }
        }

        self.isActive = true
        self.endDate = nil
    }

    // MARK: - Firestore Conversion

    func toFirestoreData() -> [String: Any] {
        // Prefer firestoreId for the athlete reference so it survives reinstalls.
        // Fall back to local UUID for athletes that haven't synced yet.
        let athleteRef = athlete?.firestoreId ?? athlete?.id.uuidString ?? ""
        return [
            "id": id.uuidString,
            "name": name,
            "athleteId": athleteRef,
            "startDate": startDate ?? Date(),
            "endDate": endDate as Any,
            "isActive": isActive,
            "sport": sport.rawValue,
            "notes": notes,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]
    }
}
