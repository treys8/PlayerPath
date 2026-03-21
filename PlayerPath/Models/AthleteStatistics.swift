//
//  AthleteStatistics.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import Foundation
import SwiftData

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

    // Pitching statistics
    var totalPitches: Int = 0
    var balls: Int = 0
    var strikes: Int = 0
    var hitByPitches: Int = 0
    var wildPitches: Int = 0
    var updatedAt: Date?

    func resetAllCounts() {
        atBats = 0; hits = 0; singles = 0; doubles = 0; triples = 0
        homeRuns = 0; runs = 0; rbis = 0; walks = 0; strikeouts = 0
        groundOuts = 0; flyOuts = 0; totalGames = 0; totalPitches = 0
        balls = 0; strikes = 0; hitByPitches = 0; wildPitches = 0
    }

    var battingAverage: Double {
        return atBats > 0 ? Double(hits) / Double(atBats) : 0.0
    }

    var onBasePercentage: Double {
        // Fix Q: Include HBP in both numerator and denominator per official OBP formula:
        // OBP = (H + BB + HBP) / (AB + BB + HBP)
        let totalPlateAppearances = atBats + walks + hitByPitches
        return totalPlateAppearances > 0 ? Double(hits + walks + hitByPitches) / Double(totalPlateAppearances) : 0.0
    }

    var sluggingPercentage: Double {
        guard atBats > 0 else { return 0.0 }
        let totalBases = singles + (doubles * 2) + (triples * 3) + (homeRuns * 4)
        return Double(totalBases) / Double(atBats)
    }

    var ops: Double {
        return onBasePercentage + sluggingPercentage
    }

    var strikePercentage: Double {
        guard totalPitches > 0 else { return 0.0 }
        return Double(strikes) / Double(totalPitches)
    }

    var hasPitchingData: Bool {
        totalPitches > 0
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
        case .ball:
            self.totalPitches += 1
            self.balls += 1
        case .strike:
            self.totalPitches += 1
            self.strikes += 1
        case .hitByPitch:
            self.totalPitches += 1
            self.hitByPitches += 1
        case .wildPitch:
            self.totalPitches += 1
            self.wildPitches += 1
        }
        self.updatedAt = Date()
    }

    func addCompletedGame() {
        self.totalGames += 1
        self.updatedAt = Date()
    }

    func addManualStatistic(singles: Int = 0, doubles: Int = 0, triples: Int = 0, homeRuns: Int = 0,
                           runs: Int = 0, rbis: Int = 0, strikeouts: Int = 0, walks: Int = 0,
                           groundOuts: Int = 0, flyOuts: Int = 0) {
        // Add hits and at bats
        let totalHits = singles + doubles + triples + homeRuns
        let totalAtBats = singles + doubles + triples + homeRuns + strikeouts + groundOuts + flyOuts

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
        self.groundOuts += groundOuts
        self.flyOuts += flyOuts

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
    var groundOuts: Int = 0
    var flyOuts: Int = 0
    var hitByPitches: Int = 0
    var createdAt: Date?

    func resetAllCounts() {
        atBats = 0; hits = 0; singles = 0; doubles = 0; triples = 0
        homeRuns = 0; runs = 0; rbis = 0; strikeouts = 0; walks = 0
        groundOuts = 0; flyOuts = 0; hitByPitches = 0
    }

    // MARK: - Computed Statistics

    var battingAverage: Double {
        return atBats > 0 ? Double(hits) / Double(atBats) : 0.0
    }

    var onBasePercentage: Double {
        let totalPlateAppearances = atBats + walks + hitByPitches
        return totalPlateAppearances > 0 ? Double(hits + walks + hitByPitches) / Double(totalPlateAppearances) : 0.0
    }

    var sluggingPercentage: Double {
        guard atBats > 0 else { return 0.0 }
        let totalBases = singles + (doubles * 2) + (triples * 3) + (homeRuns * 4)
        return Double(totalBases) / Double(atBats)
    }

    var ops: Double {
        return onBasePercentage + sluggingPercentage
    }

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
            self.groundOuts += 1
        case .flyOut:
            self.flyOuts += 1
        case .hitByPitch:
            self.hitByPitches += 1
        case .ball, .strike, .wildPitch:
            // Pitching stats are not tracked in GameStatistics - only in AthleteStatistics
            break
        }
    }

    func addManualStatistic(singles: Int = 0, doubles: Int = 0, triples: Int = 0, homeRuns: Int = 0,
                           runs: Int = 0, rbis: Int = 0, strikeouts: Int = 0, walks: Int = 0,
                           groundOuts: Int = 0, flyOuts: Int = 0) {
        // Add hits and at bats
        let totalHits = singles + doubles + triples + homeRuns
        let totalAtBats = singles + doubles + triples + homeRuns + strikeouts + groundOuts + flyOuts

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
        self.groundOuts += groundOuts
        self.flyOuts += flyOuts
    }
}
