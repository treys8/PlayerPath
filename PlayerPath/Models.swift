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
 Athlete.tournaments <-> Tournament.athletes
 Athlete.games <-> Game.athlete
 Athlete.practices <-> Practice.athlete
 Athlete.videoClips <-> VideoClip.athlete
 Athlete.statistics <-> AthleteStatistics.athlete (to-one)

 Tournament.games <-> Game.tournament
 Game.videoClips <-> VideoClip.game
 Game.gameStats <-> GameStatistics.game (to-one)

 Practice.videoClips <-> VideoClip.practice
 Practice.notes <-> PracticeNote.practice
 PlayResult.videoClip <-> VideoClip.playResult (to-one)
*/

// MARK: - User and Athlete Models
@Model
final class User {
    var id: UUID
    var username: String = ""
    var email: String = ""
    var profileImagePath: String?
    var createdAt: Date?
    var isPremium: Bool = false
    var athletes: [Athlete] = []
    
    init(username: String, email: String) {
        self.id = UUID()
        self.username = username
        self.email = email
    }
}

@Model
final class Athlete {
    var id: UUID
    var name: String = ""
    var createdAt: Date?
    var user: User?
    var tournaments: [Tournament] = []
    var games: [Game] = []
    var practices: [Practice] = []
    var videoClips: [VideoClip] = []
    var statistics: AthleteStatistics?
    
    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}

// MARK: - Tournament and Game Models
@Model
final class Tournament {
    var id: UUID
    var name: String = ""
    var date: Date?
    var location: String = ""
    var info: String = ""
    var isActive: Bool = false
    var createdAt: Date?
    var athletes: [Athlete] = []
    var games: [Game] = []
    
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
    }
}

@Model
final class Game {
    var id: UUID
    var date: Date?
    var opponent: String = ""
    var isLive: Bool = false
    var isComplete: Bool = false
    var createdAt: Date?
    var tournament: Tournament?
    var athlete: Athlete?
    var videoClips: [VideoClip] = []
    var gameStats: GameStatistics?
    
    init(date: Date, opponent: String) {
        self.id = UUID()
        self.date = date
        self.opponent = opponent
    }
}

// MARK: - Practice Models
@Model
final class Practice {
    var id: UUID
    var date: Date?
    var createdAt: Date?
    var athlete: Athlete?
    var videoClips: [VideoClip] = []
    var notes: [PracticeNote] = []
    
    init(date: Date) {
        self.id = UUID()
        self.date = date
    }
}

@Model
final class PracticeNote {
    var id: UUID
    var content: String = ""
    var createdAt: Date?
    var practice: Practice?
    
    init(content: String) {
        self.id = UUID()
        self.content = content
    }
}

// MARK: - Video and Play Result Models
@Model
final class VideoClip {
    var id: UUID
    var fileName: String = ""
    var filePath: String = ""
    var thumbnailPath: String?     // Path to thumbnail image
    var cloudURL: String?          // Firebase Storage URL
    var isUploaded: Bool = false           // Sync status
    var lastSyncDate: Date?        // Last successful sync
    var createdAt: Date?
    var playResult: PlayResult?
    var isHighlight: Bool = false
    var game: Game?
    var practice: Practice?
    var athlete: Athlete?
    
    init(fileName: String, filePath: String) {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
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
    var id: UUID
    var type: PlayResultType = PlayResultType.single
    var createdAt: Date?
    var videoClip: VideoClip?
    
    init(type: PlayResultType) {
        self.id = UUID()
        self.type = type
    }
}

// MARK: - Statistics Models
@Model
final class AthleteStatistics {
    var id: UUID
    var athlete: Athlete?
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
    }
    
    func addPlayResult(_ playResult: PlayResultType) {
        switch playResult {
        case .single:
            self.atBats += 1
            self.hits += 1
            self.singles += 1
        case .double:
            self.atBats += 1
            self.hits += 1
            self.doubles += 1
        case .triple:
            self.atBats += 1
            self.hits += 1
            self.triples += 1
        case .homeRun:
            self.atBats += 1
            self.hits += 1
            self.homeRuns += 1
        case .walk:
            self.walks += 1
        case .strikeout:
            self.atBats += 1
            self.strikeouts += 1
        case .groundOut:
            self.atBats += 1
            self.groundOuts += 1
        case .flyOut:
            self.atBats += 1
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
    var id: UUID
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
    }
    
    func addPlayResult(_ playResult: PlayResultType) {
        switch playResult {
        case .single:
            self.atBats += 1
            self.hits += 1
            self.singles += 1
        case .double:
            self.atBats += 1
            self.hits += 1
            self.doubles += 1
        case .triple:
            self.atBats += 1
            self.hits += 1
            self.triples += 1
        case .homeRun:
            self.atBats += 1
            self.hits += 1
            self.homeRuns += 1
        case .walk:
            self.walks += 1
        case .strikeout:
            self.atBats += 1
            self.strikeouts += 1
        case .groundOut:
            self.atBats += 1
            // Note: groundOuts are not tracked separately in GameStatistics
        case .flyOut:
            self.atBats += 1
            // Note: flyOuts are not tracked separately in GameStatistics
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
    var id: UUID
    var hasCompletedOnboarding: Bool = false
    var completedAt: Date?
    var createdAt: Date?
    
    init() {
        self.id = UUID()
    }
    
    func markCompleted() {
        self.hasCompletedOnboarding = true
        self.completedAt = Date()
    }
}

