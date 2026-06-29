//
//  PlayResultAccumulator.swift
//  PlayerPath
//
//  Shared play-result aggregation logic for AthleteStatistics and GameStatistics.
//  Both @Model classes hold the same counter fields; this protocol lets them share
//  a single canonical implementation of how a PlayResultType maps to counter changes.
//  Adding a new PlayResultType case requires updating one place, not four.
//

import Foundation

protocol PlayResultAccumulator: AnyObject {
    var atBats: Int { get set }
    var hits: Int { get set }
    var runs: Int { get set }
    var rbis: Int { get set }
    var singles: Int { get set }
    var doubles: Int { get set }
    var triples: Int { get set }
    var homeRuns: Int { get set }
    var walks: Int { get set }
    var strikeouts: Int { get set }
    var groundOuts: Int { get set }
    var flyOuts: Int { get set }
    var totalPitches: Int { get set }
    var balls: Int { get set }
    var strikes: Int { get set }
    var hitByPitches: Int { get set }
    var wildPitches: Int { get set }
    var pitchingStrikeouts: Int { get set }
    var pitchingWalks: Int { get set }
    var fastballPitchCount: Int { get set }
    var fastballSpeedTotal: Double { get set }
    var offspeedPitchCount: Int { get set }
    var offspeedSpeedTotal: Double { get set }
    var outsRecorded: Int { get set }
    var earnedRuns: Int { get set }
    var runsAllowed: Int { get set }
    var hitsAllowed: Int { get set }
    var homeRunsAllowed: Int { get set }
    var battersFaced: Int { get set }
}

extension PlayResultAccumulator {
    /// Applies a play result to the counter fields. Single canonical mapping used by
    /// both AthleteStatistics.addPlayResult, GameStatistics.addPlayResult, and
    /// StatisticsService recalculation paths.
    ///
    /// - Parameters:
    ///   - playResult: The play result being applied.
    ///   - pitchType: When non-nil, the clip was recorded in pitcher mode. In that mode
    ///     strikeouts/groundouts/flyouts additionally count as a strike (and groundouts/flyouts
    ///     as a pitch), mirroring the official-strike-zone interpretation.
    ///   - pitchSpeed: When provided alongside a pitchType, routed into the fastball or
    ///     off-speed velocity aggregates used by the Avg FB / Avg Off-Speed cards.
    func applyPlayResult(_ playResult: PlayResultType, pitchType: String? = nil, pitchSpeed: Double? = nil) {
        // At-bats are a batting stat. In pitcher mode (`pitchType != nil`) the shared
        // `.groundOut`/`.flyOut` cases are pitcher-induced outs, not the athlete's own
        // at-bats, so they must NOT inflate the batting line.
        if playResult.countsAsAtBat && pitchType == nil {
            self.atBats += 1
        }

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
            // Batting out only — pitcher-induced outs are credited in the
            // `pitchType != nil` block below (outs recorded / batters faced).
            if pitchType == nil { self.groundOuts += 1 }
        case .flyOut:
            if pitchType == nil { self.flyOuts += 1 }
        case .ball:
            self.totalPitches += 1
            self.balls += 1
        case .strike:
            self.totalPitches += 1
            self.strikes += 1
        case .hitByPitch:
            self.totalPitches += 1
            self.hitByPitches += 1
            self.battersFaced += 1
        case .wildPitch:
            self.totalPitches += 1
            self.wildPitches += 1
        case .batterHitByPitch:
            self.hitByPitches += 1
        case .pitchingStrikeout:
            // Inherently a pitching result (never a batting case), so it's always an
            // out recorded — credited here, not in the pitchType-gated block below.
            self.totalPitches += 1
            self.strikes += 1
            self.pitchingStrikeouts += 1
            self.battersFaced += 1
            self.outsRecorded += 1
        case .pitchingWalk:
            self.totalPitches += 1
            self.pitchingWalks += 1
            self.battersFaced += 1
        case .pitchingSingleAllowed, .pitchingDoubleAllowed, .pitchingTripleAllowed:
            // Pitcher-side hit allowed (a batter reached). Feeds WHIP / opponent AVG.
            self.hitsAllowed += 1
            self.battersFaced += 1
        case .pitchingHomeRunAllowed:
            self.hitsAllowed += 1
            self.homeRunsAllowed += 1
            self.battersFaced += 1
        }

        // Pitcher-mode disambiguation for the SHARED out cases: a `.groundOut`/`.flyOut`
        // recorded in pitcher mode is an induced out (out recorded, batter faced, a strike
        // on a pitch), not the athlete's own at-bat. Inherently-pitching cases (strikeout/
        // walk/HBP/hits-allowed) are fully handled in the switch above and don't need this.
        if pitchType != nil {
            switch playResult {
            case .groundOut, .flyOut:
                self.strikes += 1
                self.totalPitches += 1
                self.outsRecorded += 1
                self.battersFaced += 1
            default:
                break
            }
        }

        applyPitchVelocity(pitchType: pitchType, pitchSpeed: pitchSpeed)
    }

    /// Contributes a pitch's speed to the fastball/off-speed velocity aggregates.
    /// Exposed separately so clips that carry a pitch speed but no tagged play result
    /// (e.g. standalone practice pitches) can still contribute to the averages.
    func applyPitchVelocity(pitchType: String?, pitchSpeed: Double?) {
        guard let speed = pitchSpeed, speed > 0 else { return }
        if pitchType == "fastball" {
            self.fastballSpeedTotal += speed
            self.fastballPitchCount += 1
        } else if pitchType == "offspeed" {
            self.offspeedSpeedTotal += speed
            self.offspeedPitchCount += 1
        }
    }

    /// Applies a manual stat entry (e.g. past-game box-score input) to the counters.
    /// Shared by AthleteStatistics and GameStatistics — the concrete types wrap this
    /// to layer on their own side effects (e.g. AthleteStatistics stamping updatedAt).
    func applyManualStatistic(singles: Int, doubles: Int, triples: Int, homeRuns: Int,
                              runs: Int, rbis: Int, strikeouts: Int, walks: Int,
                              groundOuts: Int, flyOuts: Int, hitByPitches: Int) {
        // HBP does not count as an at-bat.
        let totalHits = singles + doubles + triples + homeRuns
        let totalAtBats = totalHits + strikeouts + groundOuts + flyOuts

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
        self.hitByPitches += hitByPitches
    }

    /// Adds every counter field from another accumulator into this one.
    /// Used by StatisticsService to roll game-level stats up into athlete/season totals.
    func addCounts(from other: some PlayResultAccumulator) {
        atBats += other.atBats
        hits += other.hits
        runs += other.runs
        rbis += other.rbis
        singles += other.singles
        doubles += other.doubles
        triples += other.triples
        homeRuns += other.homeRuns
        strikeouts += other.strikeouts
        walks += other.walks
        groundOuts += other.groundOuts
        flyOuts += other.flyOuts
        hitByPitches += other.hitByPitches
        totalPitches += other.totalPitches
        balls += other.balls
        strikes += other.strikes
        wildPitches += other.wildPitches
        pitchingStrikeouts += other.pitchingStrikeouts
        pitchingWalks += other.pitchingWalks
        fastballPitchCount += other.fastballPitchCount
        fastballSpeedTotal += other.fastballSpeedTotal
        offspeedPitchCount += other.offspeedPitchCount
        offspeedSpeedTotal += other.offspeedSpeedTotal
        outsRecorded += other.outsRecorded
        earnedRuns += other.earnedRuns
        runsAllowed += other.runsAllowed
        hitsAllowed += other.hitsAllowed
        homeRunsAllowed += other.homeRunsAllowed
        battersFaced += other.battersFaced
    }

    /// Applies a manual pitching box-score line (IP/H/R/ER/BB/K/etc.) to the counters.
    /// IP is passed as `outsRecorded` (innings × 3 + leftover outs) so totals sum correctly.
    /// Mirrors `applyManualStatistic`; the concrete types wrap this to stamp `updatedAt`.
    func applyManualPitchingStatistic(outsRecorded: Int, hitsAllowed: Int, runsAllowed: Int,
                                      earnedRuns: Int, homeRunsAllowed: Int, walks: Int,
                                      strikeouts: Int, hitByPitches: Int, wildPitches: Int,
                                      battersFaced: Int, pitches: Int, strikes: Int, balls: Int) {
        self.outsRecorded += outsRecorded
        self.hitsAllowed += hitsAllowed
        self.runsAllowed += runsAllowed
        self.earnedRuns += earnedRuns
        self.homeRunsAllowed += homeRunsAllowed
        self.pitchingWalks += walks
        self.pitchingStrikeouts += strikeouts
        self.hitByPitches += hitByPitches
        self.wildPitches += wildPitches
        self.battersFaced += battersFaced
        self.totalPitches += pitches
        self.strikes += strikes
        self.balls += balls
    }

    // MARK: - Derived Statistics

    var battingAverage: Double {
        atBats > 0 ? Double(hits) / Double(atBats) : 0.0
    }

    /// OBP = (H + BB + HBP) / (AB + BB + HBP).
    /// Simplification: sacrifice flies are not tracked for the youth audience, so they
    /// aren't in the denominator. Players who would have sac flies get a slightly
    /// inflated OBP — acceptable for this app.
    var onBasePercentage: Double {
        let plateAppearances = atBats + walks + hitByPitches
        guard plateAppearances > 0 else { return 0.0 }
        return Double(hits + walks + hitByPitches) / Double(plateAppearances)
    }

    var sluggingPercentage: Double {
        guard atBats > 0 else { return 0.0 }
        let totalBases = singles + (doubles * 2) + (triples * 3) + (homeRuns * 4)
        return Double(totalBases) / Double(atBats)
    }

    var ops: Double { onBasePercentage + sluggingPercentage }

    var averageFastballSpeed: Double {
        fastballPitchCount > 0 ? fastballSpeedTotal / Double(fastballPitchCount) : 0.0
    }

    var averageOffspeedSpeed: Double {
        offspeedPitchCount > 0 ? offspeedSpeedTotal / Double(offspeedPitchCount) : 0.0
    }

    /// Isolated Power = SLG - BA. Extra-base power independent of singles.
    var isolatedPower: Double {
        guard atBats > 0 else { return 0.0 }
        return sluggingPercentage - battingAverage
    }

    /// Contact% = (AB - K) / AB. AB already excludes walks/HBP via `countsAsAtBat`,
    /// so this matches the MLB convention of "fraction of at-bats that avoided a K."
    var contactPercentage: Double {
        guard atBats > 0 else { return 0.0 }
        return Double(atBats - strikeouts) / Double(atBats)
    }

    /// Strike % = strikes / total pitches.
    var strikePercentage: Double {
        guard totalPitches > 0 else { return 0.0 }
        return Double(strikes) / Double(totalPitches)
    }

    // MARK: - Derived Pitching Statistics

    /// True when there's any pitching data worth surfacing — pitch-tagged clips or a
    /// manual pitching line. Gates the pitching stat section / per-game pitching row.
    var hasPitchingData: Bool {
        totalPitches > 0 || outsRecorded > 0 || battersFaced > 0
            || pitchingStrikeouts > 0 || pitchingWalks > 0 || hitsAllowed > 0
    }

    /// Innings pitched as a true decimal (outs ÷ 3) — used for ERA/WHIP math.
    var inningsPitched: Double {
        Double(outsRecorded) / 3.0
    }

    /// Innings pitched in baseball notation: whole innings, then leftover outs as .0/.1/.2.
    /// e.g. 17 outs → "5.2" (5⅔). NOT a decimal — don't do arithmetic on this string.
    var inningsPitchedDisplay: String {
        "\(outsRecorded / 3).\(outsRecorded % 3)"
    }

    /// ERA = 9 × earned runs / IP = 27 × ER / outs. Zero when no outs recorded.
    var era: Double {
        guard outsRecorded > 0 else { return 0.0 }
        return Double(earnedRuns) * 27.0 / Double(outsRecorded)
    }

    /// WHIP = (walks + hits allowed) / IP = 3 × (BB + H) / outs.
    var whip: Double {
        guard outsRecorded > 0 else { return 0.0 }
        return Double(pitchingWalks + hitsAllowed) * 3.0 / Double(outsRecorded)
    }

    /// Strikeouts per 9 innings.
    var strikeoutsPer9: Double {
        guard outsRecorded > 0 else { return 0.0 }
        return Double(pitchingStrikeouts) * 27.0 / Double(outsRecorded)
    }

    /// Walks per 9 innings.
    var walksPer9: Double {
        guard outsRecorded > 0 else { return 0.0 }
        return Double(pitchingWalks) * 27.0 / Double(outsRecorded)
    }

    /// Strikeout-to-walk ratio. Nil when no walks (avoids a misleading ∞/0 display).
    var strikeoutToWalkRatio: Double? {
        guard pitchingWalks > 0 else { return nil }
        return Double(pitchingStrikeouts) / Double(pitchingWalks)
    }

    /// Opponent batting average = hits allowed / official at-bats faced.
    /// At-bats faced excludes walks and HBP. Nil when there's no usable denominator.
    var opponentAverage: Double? {
        let atBatsFaced = battersFaced - pitchingWalks - hitByPitches
        guard atBatsFaced > 0 else { return nil }
        return Double(hitsAllowed) / Double(atBatsFaced)
    }
}
