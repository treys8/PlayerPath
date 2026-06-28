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

    /// Sport for this season (baseball, softball, or golf). Source of truth
    /// for a given game's sport: read `game.season?.sport`.
    ///
    /// Optional because seasons created before the `sport` column existed have
    /// NULL in storage. Reading a non-Optional enum from NULL trips SwiftData's
    /// KVC cast and hangs `modelContext.save()` (same footgun that forced
    /// `Athlete.sport` to be optional — see Athlete.swift). The initializer
    /// always supplies a concrete value, so only legacy rows read nil; all
    /// readers fall back with `?? .baseball`.
    var sport: SportType? = SportType.baseball

    /// Optional season category for organization + recruiting context (SchemaV33),
    /// e.g. Spring / Travel / Tournament. Stored as `SeasonType` rawValue; nil
    /// until the user picks one. Use `seasonTypeValue` for typed access.
    var seasonType: String?

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

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()
    private static let yearPattern: NSRegularExpression? = try? NSRegularExpression(pattern: #"\b\d{4}\b"#)

    /// Finds a season whose start/end date range contains the given date.
    /// Prefers an active match over an archived match when ranges overlap.
    /// Returns nil if no season's range contains the date.
    static func season(containing date: Date, in seasons: [Season]) -> Season? {
        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date()
        var bestMatch: Season?
        for season in seasons {
            guard let start = season.startDate, start <= date else { continue }
            // Upper bound: an explicit endDate when present; otherwise end-of-today.
            // A nil endDate means "open through today" — the season receives today's
            // and earlier content but must NOT swallow future-dated / clock-skewed
            // imports (those exceed end-of-today and fall through to the caller's
            // `?? activeSeason`). This applies to the active season AND to an inactive
            // season created without an end date (CreateSeasonView with the "Set End
            // Date" toggle off leaves endDate nil). Bounding rather than skipping the
            // latter keeps past-dated imports routing to it instead of leaking into the
            // current season; the active-over-archived tiebreak below still wins any
            // date both seasons overlap. (Replaces the old `?? Date.distantFuture`,
            // which let any open-ended season catch-all every future date.)
            let end = season.endDate ?? endOfToday
            guard date <= end else { continue }
            if bestMatch == nil || (season.isActive && bestMatch?.isActive == false) {
                bestMatch = season
            }
        }
        return bestMatch
    }

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

    /// Number of completed games in this season
    var completedGames: Int {
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

    /// Number of practices in this season
    var practicesCount: Int {
        (practices ?? []).count
    }

    /// SF Symbol for the "games / rounds" stat, sport-aware.
    var gameUnitIcon: String {
        (sport ?? .baseball) == .golf ? "figure.golf" : "baseball.diamond.bases"
    }

    /// Plural noun for game-like events, sport-aware ("Games" vs "Rounds").
    var gameUnitNounPlural: String {
        (sport ?? .baseball) == .golf ? "Rounds" : "Games"
    }

    enum SportType: String, Codable, CaseIterable {
        case baseball = "Baseball"
        case softball = "Softball"
        case golf = "Golf"

        var displayName: String { rawValue }

        /// Explicit bridge to `Athlete.Sport` (which stores lowercase raw values). A
        /// total switch, so adding a `SportType` case fails the build here instead of
        /// silently dropping that sport in the split / spinoff migrations.
        var asAthleteSport: Sport {
            switch self {
            case .baseball: return .baseball
            case .softball: return .softball
            case .golf:     return .golf
            }
        }

        var icon: String {
            switch self {
            case .baseball: return "figure.baseball"
            case .softball: return "figure.softball"
            case .golf:     return "figure.golf"
            }
        }
    }

    /// Optional season category for organization + recruiting context (SchemaV33).
    /// Stored on `Season.seasonType` as the rawValue; access typed via
    /// `seasonTypeValue`.
    enum SeasonType: String, Codable, CaseIterable {
        case spring = "Spring"
        case summer = "Summer"
        case fall = "Fall"
        case winter = "Winter"
        case school = "School"
        case travel = "Travel"
        case tournament = "Tournament"
        case indoor = "Indoor"
        case other = "Other"

        var displayName: String { rawValue }

        var icon: String {
            switch self {
            case .spring:     return "leaf.fill"
            case .summer:     return "sun.max.fill"
            case .fall:       return "wind"
            case .winter:     return "snowflake"
            case .school:     return "graduationcap.fill"
            case .travel:     return "airplane"
            case .tournament: return "trophy.fill"
            case .indoor:     return "house.fill"
            case .other:      return "tag.fill"
            }
        }
    }

    /// Typed accessor over the stored `seasonType` rawValue (non-persisted).
    var seasonTypeValue: SeasonType? {
        get { seasonType.flatMap(SeasonType.init(rawValue:)) }
        set { seasonType = newValue?.rawValue }
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
        // Normalize stamped endDate to end-of-day so same-day games/videos
        // (or backfills filed earlier today) still fall within the season.
        let stamped = endDate ?? Date()
        self.endDate = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: stamped) ?? stamped
        self.isActive = false
        // Mark dirty + bump version so the deactivation uploads; otherwise a
        // stale remote (still isActive) re-activates this on the next sync
        // download. Same invariant the activate() loop protects.
        self.needsSync = true
        self.version += 1

        // Calculate and save season statistics
        let stats = seasonStatistics ?? AthleteStatistics()
        if seasonStatistics == nil {
            seasonStatistics = stats
        }

        // Reset before aggregating so re-archiving doesn't double-count
        stats.resetAllCounts()

        // Aggregate all game stats into season stats. Matches stats recalc —
        // include in-progress games with recorded stats so archiving doesn't
        // silently drop quick-entered live-game numbers.
        for game in (games ?? []) where game.countsTowardStats {
            if let gameStats = game.gameStats {
                stats.addCounts(from: gameStats)
            }
        }

        stats.totalGames = (games ?? []).filter { $0.countsTowardStats }.count
        stats.updatedAt = Date()
    }

    /// Activate this season (deactivates other seasons for this athlete)
    func activate() {
        // Deactivate all other seasons for this athlete and stamp their end date
        if let athlete = self.athlete {
            let now = Date()
            let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
            for season in (athlete.seasons ?? []) where season.id != self.id {
                // Only touch seasons we actually deactivate. Mark them dirty +
                // bump version so the deactivation uploads; otherwise a stale
                // remote (still isActive) re-activates them on the next sync
                // download, leaving duplicate active seasons.
                guard season.isActive else { continue }
                if season.endDate == nil {
                    season.endDate = endOfToday
                }
                season.isActive = false
                season.needsSync = true
                season.version += 1
            }
        }

        self.isActive = true
        self.endDate = nil
        // Ensure the activation itself is uploadable even if the caller forgets
        // to mark it — without this, sync can revert the activation.
        self.needsSync = true
        self.version += 1

        // Keep athlete.sport in sync with the active season. Without this the
        // hint goes stale after a sport switch — tab chrome, default sport for
        // new seasons, and seasonless-content fallback all read athlete.sport
        // directly and would otherwise lag behind the active season.
        if let athlete = self.athlete,
           let mapped = Sport(rawValue: (sport ?? .baseball).rawValue.lowercased()),
           athlete.sport != mapped {
            athlete.sport = mapped
            athlete.needsSync = true
        }
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
            "sport": (sport ?? .baseball).rawValue,
            "seasonType": seasonType as Any,
            "notes": notes,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]
    }
}
