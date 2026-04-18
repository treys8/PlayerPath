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
        if playResult.countsAsAtBat {
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
        case .batterHitByPitch:
            self.hitByPitches += 1
        case .pitchingStrikeout:
            self.totalPitches += 1
            self.pitchingStrikeouts += 1
        case .pitchingWalk:
            self.totalPitches += 1
            self.pitchingWalks += 1
        case .pitchingSingleAllowed, .pitchingDoubleAllowed, .pitchingTripleAllowed, .pitchingHomeRunAllowed:
            // Label-only tag. No counters — pitcher-side hits allowed aren't tracked as stats.
            break
        }

        // Pitcher-mode credit: strikeouts/groundouts/flyouts also count as a strike.
        // Groundouts/flyouts additionally count as a pitch (they represent contact on a pitch).
        if pitchType != nil {
            switch playResult {
            case .pitchingStrikeout:
                self.strikes += 1
            case .groundOut, .flyOut:
                self.strikes += 1
                self.totalPitches += 1
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
}
