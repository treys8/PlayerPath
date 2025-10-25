//
//  Models.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import Foundation
import SwiftData

// MARK: - User and Athlete Models
@Model
final class User {
    var id: UUID
    var username: String
    var email: String
    var createdAt: Date
    var isPremium: Bool
    var athletes: [Athlete]
    
    init(username: String, email: String) {
        self.id = UUID()
        self.username = username
        self.email = email
        self.createdAt = Date()
        self.isPremium = false
        self.athletes = []
    }
}

@Model
final class Athlete {
    var id: UUID
    var name: String
    var createdAt: Date
    var user: User?
    var tournaments: [Tournament]
    var games: [Game]
    var practices: [Practice]
    var videoClips: [VideoClip]
    var statistics: Statistics?
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.tournaments = []
        self.games = []
        self.practices = []
        self.videoClips = []
    }
}

// MARK: - Tournament and Game Models
@Model
final class Tournament {
    var id: UUID
    var name: String
    var date: Date
    var location: String
    var info: String
    var isActive: Bool
    var createdAt: Date
    var athlete: Athlete?
    var games: [Game]
    
    init(name: String, date: Date, location: String, info: String = "") {
        self.id = UUID()
        self.name = name
        self.date = date
        self.location = location
        self.info = info
        self.isActive = false
        self.createdAt = Date()
        self.games = []
    }
}

@Model
final class Game {
    var id: UUID
    var date: Date
    var opponent: String
    var isLive: Bool
    var isComplete: Bool
    var createdAt: Date
    var tournament: Tournament?
    var athlete: Athlete?
    var videoClips: [VideoClip]
    var gameStats: GameStatistics?
    
    init(date: Date, opponent: String) {
        self.id = UUID()
        self.date = date
        self.opponent = opponent
        self.isLive = false
        self.isComplete = false
        self.createdAt = Date()
        self.videoClips = []
    }
}

// MARK: - Practice Models
@Model
final class Practice {
    var id: UUID
    var date: Date
    var createdAt: Date
    var athlete: Athlete?
    var videoClips: [VideoClip]
    var notes: [PracticeNote]
    
    init(date: Date) {
        self.id = UUID()
        self.date = date
        self.createdAt = Date()
        self.videoClips = []
        self.notes = []
    }
}

@Model
final class PracticeNote {
    var id: UUID
    var content: String
    var createdAt: Date
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
    var id: UUID
    var fileName: String
    var filePath: String
    var createdAt: Date
    var playResult: PlayResult?
    var isHighlight: Bool
    var game: Game?
    var practice: Practice?
    var athlete: Athlete?
    
    init(fileName: String, filePath: String) {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
        self.createdAt = Date()
        self.isHighlight = false
    }
}

enum PlayResultType: String, CaseIterable, Codable {
    case single = "Single"
    case double = "Double"
    case triple = "Triple"
    case homeRun = "Home Run"
    case walk = "Walk"
    case strikeout = "Strikeout"
    case groundOut = "Ground Out"
    case flyOut = "Fly Out"
    
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
}

@Model
final class PlayResult {
    var id: UUID
    var type: PlayResultType
    var createdAt: Date
    var videoClip: VideoClip?
    
    init(type: PlayResultType) {
        self.id = UUID()
        self.type = type
        self.createdAt = Date()
    }
}

// MARK: - Statistics Models
@Model
final class Statistics {
    var id: UUID
    var athlete: Athlete?
    var totalGames: Int
    var atBats: Int
    var hits: Int
    var singles: Int
    var doubles: Int
    var triples: Int
    var homeRuns: Int
    var runs: Int
    var rbis: Int
    var walks: Int
    var strikeouts: Int
    var groundOuts: Int
    var flyOuts: Int
    var updatedAt: Date
    
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
        self.totalGames = 0
        self.atBats = 0
        self.hits = 0
        self.singles = 0
        self.doubles = 0
        self.triples = 0
        self.homeRuns = 0
        self.runs = 0
        self.rbis = 0
        self.walks = 0
        self.strikeouts = 0
        self.groundOuts = 0
        self.flyOuts = 0
        self.updatedAt = Date()
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
    var atBats: Int
    var hits: Int
    var runs: Int
    var singles: Int
    var doubles: Int
    var triples: Int
    var homeRuns: Int
    var rbis: Int
    var strikeouts: Int
    var walks: Int
    var createdAt: Date
    
    init() {
        self.id = UUID()
        self.atBats = 0
        self.hits = 0
        self.runs = 0
        self.singles = 0
        self.doubles = 0
        self.triples = 0
        self.homeRuns = 0
        self.rbis = 0
        self.strikeouts = 0
        self.walks = 0
        self.createdAt = Date()
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