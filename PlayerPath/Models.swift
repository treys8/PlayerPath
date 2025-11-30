//
//  Models.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import Foundation
import SwiftData


/*
 Inverse relationships mapping for CloudKit/SwiftData:

 User.athletes <-> Athlete.user
 Athlete.seasons <-> Season.athlete
 Athlete.tournaments <-> Tournament.athletes
 Athlete.games <-> Game.athlete
 Athlete.practices <-> Practice.athlete
 Athlete.videoClips <-> VideoClip.athlete
 Athlete.statistics <-> AthleteStatistics.athlete (to-one)
 Athlete.coaches <-> Coach.athlete

 Season.games <-> Game.season
 Season.practices <-> Practice.season
 Season.videoClips <-> VideoClip.season
 Season.tournaments <-> Tournament.season
 Season.seasonStatistics <-> AthleteStatistics (to-one)

 Tournament.games <-> Game.tournament
 Tournament.season <-> Season.tournaments
 Game.videoClips <-> VideoClip.game
 Game.gameStats <-> GameStatistics.game (to-one)
 Game.season <-> Season.games

 Practice.videoClips <-> VideoClip.practice
 Practice.notes <-> PracticeNote.practice
 Practice.season <-> Season.practices

 VideoClip.season <-> Season.videoClips
 PlayResult.videoClip <-> VideoClip.playResult (to-one)
*/

// MARK: - User and Athlete Models
@Model
final class User {
    var id: UUID = UUID()
    var username: String = ""
    var email: String = ""
    var profileImagePath: String?
    var createdAt: Date?
    var isPremium: Bool = false
    @Relationship(inverse: \Athlete.user) var athletes: [Athlete]?

    init(username: String, email: String) {
        self.id = UUID()
        self.username = username
        self.email = email
        self.createdAt = Date()
    }
}

@Model
final class Athlete {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date?
    var user: User?
    @Relationship(inverse: \Season.athlete) var seasons: [Season]?
    var tournaments: [Tournament]?
    @Relationship(inverse: \Game.athlete) var games: [Game]?
    @Relationship(inverse: \Practice.athlete) var practices: [Practice]?
    @Relationship(inverse: \VideoClip.athlete) var videoClips: [VideoClip]?
    @Relationship(inverse: \AthleteStatistics.athlete) var statistics: AthleteStatistics?
    @Relationship(inverse: \Coach.athlete) var coaches: [Coach]?

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
}

// MARK: - Season Model
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
    @Relationship(inverse: \Tournament.season) var tournaments: [Tournament]?

    /// Season-specific statistics (calculated when season is archived)
    @Relationship(inverse: \AthleteStatistics.season) var seasonStatistics: AthleteStatistics?
    
    /// Notes about the season (goals, achievements, etc.)
    var notes: String = ""
    
    /// Sport for this season (baseball or softball)
    var sport: SportType = SportType.baseball
    
    /// Computed display name with year range
    var displayName: String {
        // If name already contains a year (4 digits), just return it
        let yearPattern = #"\b\d{4}\b"#
        if let _ = name.range(of: yearPattern, options: .regularExpression) {
            return name
        }
        
        // Otherwise, append year from dates
        if let start = startDate, let end = endDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            let startYear = formatter.string(from: start)
            let endYear = formatter.string(from: end)
            
            if startYear == endYear {
                return "\(name) \(startYear)"
            } else {
                return "\(name) \(startYear)-\(endYear)"
            }
        } else if let start = startDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            return "\(name) \(formatter.string(from: start))"
        }
        return name
    }
    
    /// Is this season archived (ended)?
    var isArchived: Bool {
        return !isActive && endDate != nil
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
            }
        }
        
        stats.totalGames = totalGames
        stats.updatedAt = Date()
    }
    
    /// Activate this season (deactivates other seasons for this athlete)
    func activate() {
        self.isActive = true
        self.endDate = nil
    }
}

// MARK: - Tournament and Game Models
@Model
final class Tournament {
    var id: UUID = UUID()
    var name: String = ""
    var date: Date?
    var location: String = ""
    var info: String = ""
    var isActive: Bool = false
    var createdAt: Date?
    @Relationship(inverse: \Athlete.tournaments) var athletes: [Athlete]?
    @Relationship(inverse: \Game.tournament) var games: [Game]?
    var season: Season?
    
    // Backward-compatibility shim for older code paths
    var isLive: Bool {
        get { isActive }
        set { isActive = newValue }
    }
    
    // Dashboard sorting shim: some views reference startDate
    var startDate: Date? {
        get { date }
        set { date = newValue }
    }
    
    init(name: String, date: Date, location: String, info: String = "") {
        self.id = UUID()
        self.name = name
        self.date = date
        self.location = location
        self.info = info
        self.createdAt = Date()
    }
}

@Model
final class Game {
    var id: UUID = UUID()
    var date: Date?
    var opponent: String = ""
    var isLive: Bool = false
    var isComplete: Bool = false
    var createdAt: Date?
    var tournament: Tournament?
    var athlete: Athlete?
    var season: Season?
    @Relationship(inverse: \VideoClip.game) var videoClips: [VideoClip]?
    @Relationship(inverse: \GameStatistics.game) var gameStats: GameStatistics?

    init(date: Date, opponent: String) {
        self.id = UUID()
        self.date = date
        self.opponent = opponent
        self.createdAt = Date()
    }
}

// MARK: - Practice Models
@Model
final class Practice {
    var id: UUID = UUID()
    var date: Date?
    var createdAt: Date?
    var athlete: Athlete?
    var season: Season?
    @Relationship(inverse: \VideoClip.practice) var videoClips: [VideoClip]?
    @Relationship(inverse: \PracticeNote.practice) var notes: [PracticeNote]?

    init(date: Date) {
        self.id = UUID()
        self.date = date
        self.createdAt = Date()
    }
}

@Model
final class PracticeNote {
    var id: UUID = UUID()
    var content: String = ""
    var createdAt: Date?
    var practice: Practice?

    init(content: String) {
        self.id = UUID()
        self.content = content
        self.createdAt = Date()
    }
}

// MARK: - Video and Play Result Models
@Model
final class VideoClip {
    var id: UUID = UUID()
    var fileName: String = ""
    var filePath: String = ""
    var thumbnailPath: String?     // Path to thumbnail image
    var cloudURL: String?          // Firebase Storage URL
    var isUploaded: Bool = false           // Sync status
    var lastSyncDate: Date?        // Last successful sync
    var createdAt: Date?
    @Relationship(inverse: \PlayResult.videoClip) var playResult: PlayResult?
    var isHighlight: Bool = false
    var game: Game?
    var practice: Practice?
    var athlete: Athlete?
    var season: Season?
    
    init(fileName: String, filePath: String) {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
        self.createdAt = Date()
    }
    
    // Computed properties for sync status
    var needsUpload: Bool {
        return !isUploaded && cloudURL == nil
    }
    
    var isAvailableOffline: Bool {
        return FileManager.default.fileExists(atPath: filePath)
    }
}

enum PlayResultType: Int, CaseIterable, Codable {
    case single
    case double
    case triple
    case homeRun
    case walk
    case strikeout
    case groundOut
    case flyOut
    
    var isHit: Bool {
        switch self {
        case .single, .double, .triple, .homeRun:
            return true
        default:
            return false
        }
    }
    
    /// Determines if this result counts as an official at-bat
    /// Baseball rules: Walks, HBP, sac flies, and sac bunts do NOT count as at-bats
    var countsAsAtBat: Bool {
        switch self {
        case .walk:
            return false // Walks don't count as at-bats
        case .single, .double, .triple, .homeRun, .strikeout, .groundOut, .flyOut:
            return true // Hits and outs count as at-bats
        }
    }
    
    var isHighlight: Bool {
        switch self {
        case .single, .double, .triple, .homeRun:
            return true
        default:
            return false
        }
    }
    
    var bases: Int {
        switch self {
        case .single: return 1
        case .double: return 2
        case .triple: return 3
        case .homeRun: return 4
        default: return 0
        }
    }
    
    var displayName: String {
        switch self {
        case .single: return "Single"
        case .double: return "Double"
        case .triple: return "Triple"
        case .homeRun: return "Home Run"
        case .walk: return "Walk"
        case .strikeout: return "Strikeout"
        case .groundOut: return "Ground Out"
        case .flyOut: return "Fly Out"
        }
    }
}

@Model
final class PlayResult {
    var id: UUID = UUID()
    var type: PlayResultType = PlayResultType.single
    var createdAt: Date?
    var videoClip: VideoClip?

    init(type: PlayResultType) {
        self.id = UUID()
        self.type = type
        self.createdAt = Date()
    }
}

// MARK: - Statistics Models
@Model
final class AthleteStatistics {
    var id: UUID = UUID()
    var athlete: Athlete?
    var season: Season?  // Inverse relationship for Season.seasonStatistics
    var totalGames: Int = 0
    var atBats: Int = 0
    var hits: Int = 0
    var singles: Int = 0
    var doubles: Int = 0
    var triples: Int = 0
    var homeRuns: Int = 0
    var runs: Int = 0
    var rbis: Int = 0
    var walks: Int = 0
    var strikeouts: Int = 0
    var groundOuts: Int = 0
    var flyOuts: Int = 0
    var updatedAt: Date?
    
    var battingAverage: Double {
        return atBats > 0 ? Double(hits) / Double(atBats) : 0.0
    }
    
    var onBasePercentage: Double {
        let totalPlateAppearances = atBats + walks
        return totalPlateAppearances > 0 ? Double(hits + walks) / Double(totalPlateAppearances) : 0.0
    }
    
    var sluggingPercentage: Double {
        guard atBats > 0 else { return 0.0 }
        let totalBases = singles + (doubles * 2) + (triples * 3) + (homeRuns * 4)
        return Double(totalBases) / Double(atBats)
    }
    
    init() {
        self.id = UUID()
        self.updatedAt = Date()
    }
    
    func addPlayResult(_ playResult: PlayResultType) {
        // Update at-bats (only if this result counts as an at-bat)
        if playResult.countsAsAtBat {
            self.atBats += 1
        }
        
        // Update specific result counts
        switch playResult {
        case .single:
            self.hits += 1
            self.singles += 1
        case .double:
            self.hits += 1
            self.doubles += 1
        case .triple:
            self.hits += 1
            self.triples += 1
        case .homeRun:
            self.hits += 1
            self.homeRuns += 1
        case .walk:
            self.walks += 1
        case .strikeout:
            self.strikeouts += 1
        case .groundOut:
            self.groundOuts += 1
        case .flyOut:
            self.flyOuts += 1
        }
        self.updatedAt = Date()
    }
    
    func addCompletedGame() {
        self.totalGames += 1
        self.updatedAt = Date()
        print("Statistics: Added completed game, total games now: \(self.totalGames)")
    }
    
    func addManualStatistic(singles: Int = 0, doubles: Int = 0, triples: Int = 0, homeRuns: Int = 0,
                           runs: Int = 0, rbis: Int = 0, strikeouts: Int = 0, walks: Int = 0) {
        // Add hits and at bats
        let totalHits = singles + doubles + triples + homeRuns
        let totalAtBats = singles + doubles + triples + homeRuns + strikeouts
        
        self.singles += singles
        self.doubles += doubles
        self.triples += triples
        self.homeRuns += homeRuns
        self.hits += totalHits
        self.atBats += totalAtBats
        self.runs += runs
        self.rbis += rbis
        self.strikeouts += strikeouts
        self.walks += walks
        
        self.updatedAt = Date()
    }
}

@Model
final class GameStatistics {
    var id: UUID = UUID()
    var game: Game?
    var atBats: Int = 0
    var hits: Int = 0
    var runs: Int = 0
    var singles: Int = 0
    var doubles: Int = 0
    var triples: Int = 0
    var homeRuns: Int = 0
    var rbis: Int = 0
    var strikeouts: Int = 0
    var walks: Int = 0
    var createdAt: Date?
    
    init() {
        self.id = UUID()
        self.createdAt = Date()
    }
    
    func addPlayResult(_ playResult: PlayResultType) {
        // Update at-bats (only if this result counts as an at-bat)
        if playResult.countsAsAtBat {
            self.atBats += 1
        }
        
        // Update specific result counts
        switch playResult {
        case .single:
            self.hits += 1
            self.singles += 1
        case .double:
            self.hits += 1
            self.doubles += 1
        case .triple:
            self.hits += 1
            self.triples += 1
        case .homeRun:
            self.hits += 1
            self.homeRuns += 1
        case .walk:
            self.walks += 1
        case .strikeout:
            self.strikeouts += 1
        case .groundOut:
            // Note: groundOuts are not tracked separately in GameStatistics
            break
        case .flyOut:
            // Note: flyOuts are not tracked separately in GameStatistics
            break
        }
        print("GameStatistics: Added play result \(playResult.rawValue). New totals - Hits: \(self.hits), At Bats: \(self.atBats)")
    }
    
    func addManualStatistic(singles: Int = 0, doubles: Int = 0, triples: Int = 0, homeRuns: Int = 0,
                           runs: Int = 0, rbis: Int = 0, strikeouts: Int = 0, walks: Int = 0) {
        // Add hits and at bats
        let totalHits = singles + doubles + triples + homeRuns
        let totalAtBats = singles + doubles + triples + homeRuns + strikeouts
        
        self.singles += singles
        self.doubles += doubles
        self.triples += triples
        self.homeRuns += homeRuns
        self.hits += totalHits
        self.atBats += totalAtBats
        self.runs += runs
        self.rbis += rbis
        self.strikeouts += strikeouts
        self.walks += walks
    }
}

// MARK: - Onboarding Models
@Model
final class OnboardingProgress {
    var id: UUID = UUID()
    var hasCompletedOnboarding: Bool = false
    var completedAt: Date?
    var createdAt: Date?

    init() {
        self.id = UUID()
        self.createdAt = Date()
    }

    func markCompleted() {
        self.hasCompletedOnboarding = true
        self.completedAt = Date()
    }
}

// MARK: - Coach Model
@Model
final class Coach {
    var id: UUID = UUID()
    var name: String = ""
    var role: String = ""
    var phone: String = ""
    var email: String = ""
    var notes: String = ""
    var createdAt: Date?
    var athlete: Athlete?

    init(name: String, role: String = "", phone: String = "", email: String = "", notes: String = "") {
        self.id = UUID()
        self.name = name
        self.role = role
        self.phone = phone
        self.email = email
        self.notes = notes
        self.createdAt = Date()
    }
}

