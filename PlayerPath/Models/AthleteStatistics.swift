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
final class AthleteStatistics: PlayResultAccumulator {
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
    var pitchingStrikeouts: Int = 0
    var pitchingWalks: Int = 0
    // Pitch velocity tracking — populated from VideoClip.pitchType
    var fastballPitchCount: Int = 0
    var fastballSpeedTotal: Double = 0
    var offspeedPitchCount: Int = 0
    var offspeedSpeedTotal: Double = 0
    var updatedAt: Date?

    func resetAllCounts() {
        atBats = 0; hits = 0; singles = 0; doubles = 0; triples = 0
        homeRuns = 0; runs = 0; rbis = 0; walks = 0; strikeouts = 0
        groundOuts = 0; flyOuts = 0; totalGames = 0; totalPitches = 0
        balls = 0; strikes = 0; hitByPitches = 0; wildPitches = 0
        pitchingStrikeouts = 0; pitchingWalks = 0
        fastballPitchCount = 0; fastballSpeedTotal = 0
        offspeedPitchCount = 0; offspeedSpeedTotal = 0
    }

    var hasPitchingData: Bool {
        totalPitches > 0
    }

    init() {
        self.id = UUID()
        self.updatedAt = Date()
    }

    func addPlayResult(_ playResult: PlayResultType, pitchType: String? = nil, pitchSpeed: Double? = nil) {
        applyPlayResult(playResult, pitchType: pitchType, pitchSpeed: pitchSpeed)
        self.updatedAt = Date()
    }

    func addCompletedGame() {
        self.totalGames += 1
        self.updatedAt = Date()
    }

    func addManualStatistic(singles: Int = 0, doubles: Int = 0, triples: Int = 0, homeRuns: Int = 0,
                           runs: Int = 0, rbis: Int = 0, strikeouts: Int = 0, walks: Int = 0,
                           groundOuts: Int = 0, flyOuts: Int = 0, hitByPitches: Int = 0) {
        applyManualStatistic(singles: singles, doubles: doubles, triples: triples, homeRuns: homeRuns,
                             runs: runs, rbis: rbis, strikeouts: strikeouts, walks: walks,
                             groundOuts: groundOuts, flyOuts: flyOuts, hitByPitches: hitByPitches)
        self.updatedAt = Date()
    }
}

@Model
final class GameStatistics: PlayResultAccumulator {
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
    var totalPitches: Int = 0
    var balls: Int = 0
    var strikes: Int = 0
    var wildPitches: Int = 0
    var pitchingStrikeouts: Int = 0
    var pitchingWalks: Int = 0
    // Pitch velocity tracking — populated from VideoClip.pitchType
    var fastballPitchCount: Int = 0
    var fastballSpeedTotal: Double = 0
    var offspeedPitchCount: Int = 0
    var offspeedSpeedTotal: Double = 0
    var createdAt: Date?

    /// Sticky flag: true when any counter value on this object came from
    /// ManualStatisticsEntryView or QuickStatisticsEntryView (as opposed to
    /// being derived from VideoClip.playResult tags).
    ///
    /// When true, `StatisticsService.recalculateGameStatistics` is a no-op
    /// for this game — manual entries are the source of truth and video
    /// tagging on the same game doesn't affect counters. This is the gate
    /// that makes manual/quick-entered stats survive video sync events.
    var hasManualEntry: Bool = false

    func resetAllCounts() {
        atBats = 0; hits = 0; singles = 0; doubles = 0; triples = 0
        homeRuns = 0; runs = 0; rbis = 0; strikeouts = 0; walks = 0
        groundOuts = 0; flyOuts = 0; hitByPitches = 0
        totalPitches = 0; balls = 0; strikes = 0; wildPitches = 0
        pitchingStrikeouts = 0; pitchingWalks = 0
        fastballPitchCount = 0; fastballSpeedTotal = 0
        offspeedPitchCount = 0; offspeedSpeedTotal = 0
    }

    init() {
        self.id = UUID()
        self.createdAt = Date()
    }

    func addPlayResult(_ playResult: PlayResultType, pitchType: String? = nil, pitchSpeed: Double? = nil) {
        applyPlayResult(playResult, pitchType: pitchType, pitchSpeed: pitchSpeed)
    }

    func addManualStatistic(singles: Int = 0, doubles: Int = 0, triples: Int = 0, homeRuns: Int = 0,
                           runs: Int = 0, rbis: Int = 0, strikeouts: Int = 0, walks: Int = 0,
                           groundOuts: Int = 0, flyOuts: Int = 0, hitByPitches: Int = 0) {
        applyManualStatistic(singles: singles, doubles: doubles, triples: triples, homeRuns: homeRuns,
                             runs: runs, rbis: rbis, strikeouts: strikeouts, walks: walks,
                             groundOuts: groundOuts, flyOuts: flyOuts, hitByPitches: hitByPitches)
    }
}
