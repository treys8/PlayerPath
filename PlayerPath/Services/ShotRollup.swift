//
//  ShotRollup.swift
//  PlayerPath
//
//  Derives a hole's `GolfScoreWriter.HoleInput` (score / FIR / GIR / putts /
//  penalties) from its ordered non-putt shots plus the putt count. Pure and
//  synchronous — the entry view feeds the result into the existing
//  upsertHole → mirrorTotalScore → upsertReelIfNeeded → save sequence, so the
//  HoleScore stays fully DERIVED and nothing is entered twice.
//
//  Descriptive stats (miss direction, scrambling, sand saves) are NOT produced
//  here — they're recomputed on demand from `hole.shots` by the stats layer, so
//  there's no rollup/storage divergence to keep in sync.
//

import Foundation

@MainActor
enum ShotRollup {

    /// Derives the hole input. `shots` must be the hole's non-putt shots ordered
    /// by `shotNumber`; `putts` is the single putt count (nil = not yet entered).
    static func deriveInput(holeNumber: Int, par: Int, shots: [Shot], putts: Int?) -> GolfScoreWriter.HoleInput {
        let penaltyStrokes = shots.reduce(0) { $0 + $1.penaltyStrokes }
        // Strokes taken = every logged non-putt shot + putts + penalty strokes.
        // (A holed chip counts as a shot with putts 0; penalties add, never
        // replace a shot.)
        let score = shots.count + (putts ?? 0) + penaltyStrokes

        return GolfScoreWriter.HoleInput(
            holeNumber: holeNumber,
            par: par,
            score: score,
            putts: putts,
            fairwayHit: fairwayHit(par: par, shots: shots),
            greenInRegulation: greenInRegulation(par: par, shots: shots, putts: putts),
            penalties: penaltyStrokes > 0 ? penaltyStrokes : nil
        )
    }

    /// FIR — par 4+ only (par 3s have no fairway). Read from the tee shot.
    static func fairwayHit(par: Int, shots: [Shot]) -> Bool? {
        guard par >= 4, let tee = shots.first(where: { $0.lie == .tee }) else { return nil }
        switch tee.outcome {
        case .fairway:
            return true
        case .missLeft, .missRight, .short, .long, .fringe, .bunker:
            return false
        default:
            return nil
        }
    }

    /// GIR — the ball reached the green (outcome `.green`/`.holed`/`.close`/`.on`)
    /// on or before the regulation stroke (`par - 2`). nil until the hole has
    /// enough information to decide.
    static func greenInRegulation(par: Int, shots: [Shot], putts: Int?) -> Bool? {
        let regulationStroke = max(1, par - 2)
        // GIR = the ball reached the putting SURFACE in regulation. A greenside
        // chip that ends on/close to the green (.close/.on), or a holed chip from
        // sand/fringe, is a scramble — not a GIR — so exclude those.
        func reachesGreenInReg(_ s: Shot) -> Bool {
            switch s.outcome {
            case .green:  return true
            case .holed:  return s.lie != .sand && s.lie != .fringe   // holed approach, not a greenside chip-in
            default:      return false                                // .close/.on are greenside results
            }
        }
        if let reach = shots.first(where: reachesGreenInReg) {
            return reach.shotNumber <= regulationStroke
        }
        // No qualifying shot. Only commit to `false` once the hole looks complete
        // (a mid-entry hole shouldn't read "missed green" prematurely).
        return isComplete(shots: shots, putts: putts) ? false : nil
    }

    /// A hole is complete when the last shot holed out, or the ball reached the
    /// green and at least one putt has been entered.
    static func isComplete(shots: [Shot], putts: Int?) -> Bool {
        if shots.last?.outcome == .holed { return true }
        if shots.contains(where: { $0.outcome.reachedGreen }) && (putts ?? 0) >= 1 { return true }
        return false
    }
}
