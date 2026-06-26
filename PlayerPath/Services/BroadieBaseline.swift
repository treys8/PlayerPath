//
//  BroadieBaseline.swift
//  PlayerPath
//
//  Pure Strokes-Gained baseline tables for golf analytics (no SwiftData, no UI).
//  Values are Mark Broadie's public PGA Tour "expected strokes to hole out"
//  baseline (Every Shot Counts, 2014), keyed by lie × distance with linear
//  interpolation between anchors and flat extrapolation past the ends. Because
//  the app collects no course rating/slope, everything that consumes this is
//  labeled "Est." in the UI.
//
//  Approach/tee distances are in YARDS; the putting table is in FEET. The
//  putting curve is unused in v1 (no putt distance is captured) and kept only so
//  a future per-putt mode needs no new table.
//

import Foundation

enum BroadieBaseline {

    /// The lie buckets the public Broadie table provides a distance curve for.
    /// The app's `ShotLie` set is reduced onto these (see `baselineLie`).
    enum BaselineLie {
        case tee, fairway, rough, sand, recovery
    }

    /// Reduce an app `ShotLie` onto a baseline curve. Returns nil for `.green`,
    /// which is putting (handled by a separate feet-based table, deferred in v1).
    /// `.fringe` rides the fairway curve (short grass, no Broadie fringe curve);
    /// `.water` rides the recovery curve (it's a manual-only penal lie).
    static func baselineLie(for lie: ShotLie) -> BaselineLie? {
        switch lie {
        case .tee:               return .tee
        case .fairway, .fringe:  return .fairway
        case .rough:             return .rough
        case .sand:              return .sand
        case .recovery, .water:  return .recovery
        case .green:             return nil
        }
    }

    /// Expected strokes to hole out from `lie` at `distanceYards`. nil when the
    /// lie is `.green` (putting). Clamps to the table ends.
    static func expectedStrokes(lie: ShotLie, distanceYards: Int) -> Double? {
        guard let bucket = baselineLie(for: lie) else { return nil }
        return interpolate(table(for: bucket), at: Double(distanceYards))
    }

    /// Expected putts from `distanceFeet`. UNUSED in v1 (no putt distance is
    /// captured); kept for a future per-putt mode. Clamps to the table ends.
    static func expectedPutts(distanceFeet: Double) -> Double {
        interpolate(puttingFeet, at: distanceFeet)
    }

    // MARK: - Interpolation

    /// Linear interpolation over an ascending `(x, y)` table. Below the first
    /// anchor returns the first `y`; above the last returns the last `y`.
    private static func interpolate(_ table: [(x: Double, y: Double)], at x: Double) -> Double {
        guard let first = table.first else { return 0 }
        if x <= first.x { return first.y }
        guard let last = table.last else { return first.y }
        if x >= last.x { return last.y }
        // Find the bracketing pair. Tables are tiny (≤30 rows) so a linear scan
        // is fine and keeps the type-checker fast.
        for i in 1..<table.count {
            let lo = table[i - 1], hi = table[i]
            if x <= hi.x {
                let span = hi.x - lo.x
                guard span > 0 else { return lo.y }
                let t = (x - lo.x) / span
                return lo.y + t * (hi.y - lo.y)
            }
        }
        return last.y
    }

    private static func table(for bucket: BaselineLie) -> [(x: Double, y: Double)] {
        switch bucket {
        case .tee:      return teeYards
        case .fairway:  return fairwayYards
        case .rough:    return roughYards
        case .sand:     return sandYards
        case .recovery: return recoveryYards
        }
    }

    // MARK: - Tables (yards → expected strokes; Broadie PGA Tour baseline)

    /// Tee curve spans par-3 (short) through par-5 (long) distances so a single
    /// `expectedStrokes(.tee, holeYardage)` resolves any hole.
    private static let teeYards: [(x: Double, y: Double)] = [
        (100, 2.92), (120, 2.96), (140, 2.99), (160, 3.02), (180, 3.06),
        (200, 3.13), (220, 3.20), (240, 3.27), (260, 3.33), (280, 3.40),
        (300, 3.46), (320, 3.53), (340, 3.60), (360, 3.67), (380, 3.73),
        (400, 3.79), (420, 3.86), (440, 3.92), (460, 3.99), (480, 4.05),
        (500, 4.12), (520, 4.20), (540, 4.28), (560, 4.36), (580, 4.45),
        (600, 4.55)
    ]

    private static let fairwayYards: [(x: Double, y: Double)] = [
        (20, 2.40), (40, 2.60), (60, 2.70), (80, 2.75), (100, 2.80),
        (120, 2.85), (140, 2.91), (160, 2.98), (180, 3.08), (200, 3.19),
        (220, 3.32), (240, 3.45), (260, 3.58), (280, 3.69), (300, 3.78),
        (320, 3.84), (340, 3.88), (360, 3.91), (380, 3.94), (400, 3.97),
        (420, 4.00), (440, 4.03), (460, 4.06), (480, 4.09), (500, 4.12)
    ]

    private static let roughYards: [(x: Double, y: Double)] = [
        (20, 2.59), (40, 2.78), (60, 2.91), (80, 2.96), (100, 3.02),
        (120, 3.08), (140, 3.15), (160, 3.23), (180, 3.31), (200, 3.42),
        (220, 3.53), (240, 3.64), (260, 3.74), (280, 3.83), (300, 3.92),
        (320, 3.99), (340, 4.05), (360, 4.10), (380, 4.14), (400, 4.19),
        (420, 4.23), (440, 4.27), (460, 4.31), (480, 4.35), (500, 4.39)
    ]

    private static let sandYards: [(x: Double, y: Double)] = [
        (20, 2.53), (40, 2.82), (60, 3.15), (80, 3.21), (100, 3.24),
        (120, 3.28), (140, 3.33), (160, 3.39), (180, 3.45), (200, 3.55),
        (220, 3.65), (240, 3.74), (260, 3.83), (280, 3.92), (300, 4.00),
        (320, 4.06), (340, 4.12), (360, 4.17), (380, 4.21), (400, 4.26),
        (420, 4.30), (440, 4.34), (460, 4.37), (480, 4.41), (500, 4.45)
    ]

    private static let recoveryYards: [(x: Double, y: Double)] = [
        (20, 3.00), (40, 3.20), (60, 3.35), (80, 3.42), (100, 3.45),
        (120, 3.51), (140, 3.57), (160, 3.63), (180, 3.69), (200, 3.77),
        (220, 3.84), (240, 3.91), (260, 3.98), (280, 4.05), (300, 4.12),
        (320, 4.18), (340, 4.22), (360, 4.25), (380, 4.28), (400, 4.31),
        (420, 4.34), (440, 4.37), (460, 4.40), (480, 4.43), (500, 4.46)
    ]

    /// Putting baseline in FEET. UNUSED in v1.
    private static let puttingFeet: [(x: Double, y: Double)] = [
        (1, 1.001), (2, 1.009), (3, 1.053), (4, 1.147), (5, 1.256),
        (6, 1.357), (7, 1.443), (8, 1.515), (9, 1.575), (10, 1.626),
        (15, 1.799), (20, 1.898), (30, 2.018), (40, 2.092), (50, 2.150),
        (60, 2.207), (90, 2.400)
    ]

    // MARK: - DEBUG self-check

    #if DEBUG
    /// Sanity-checks the tables + the telescoping identity once. Asserts so a
    /// table typo or a sign flip trips in development; no-op in release. Called
    /// once from `ShotStrokesGained.compute`.
    static func runSelfCheck() {
        // (a) A ~150-yard tee shot (mid par-3) ≈ 3.0 strokes.
        let tee150 = expectedStrokes(lie: .tee, distanceYards: 150) ?? 0
        assert(abs(tee150 - 3.0) < 0.1, "tee(150) baseline drifted: \(tee150)")

        // (b) Tee curve is monotonically non-decreasing in distance.
        var prev = -1.0
        for d in stride(from: 100, through: 600, by: 20) {
            let v = expectedStrokes(lie: .tee, distanceYards: d) ?? 0
            assert(v >= prev - 0.0001, "tee curve not monotonic at \(d): \(v) < \(prev)")
            prev = v
        }

        // (c) Telescoping identity on a synthetic par-4 birdie (400 yds, score 3:
        // tee → fairway approach → one putt holed). Σ per-shot SG must equal
        // E(.tee, 400) − score. Putting term included here only to prove the
        // math reconciles; the live Layer-2 walk excludes putts by design.
        let eTee   = expectedStrokes(lie: .tee, distanceYards: 400)!      // start of hole
        let eFwy   = expectedStrokes(lie: .fairway, distanceYards: 150)!  // after the tee shot
        let ePutt  = expectedPutts(distanceFeet: 20)                      // after the approach (on green)
        let sgTee   = eTee  - eFwy  - 1            // tee shot
        let sgAppr  = eFwy  - ePutt - 1            // approach to 20 ft
        let sgPutt  = ePutt - 0     - 1            // holed putt
        let sumSG = sgTee + sgAppr + sgPutt
        let identity = eTee - 3.0                  // E(start) − score
        assert(abs(sumSG - identity) < 0.0001, "telescoping broke: Σ=\(sumSG) vs E−score=\(identity)")

        // (d) A sub-par hole gains strokes: a par-4 birdie is positive SG.
        assert(eTee - 3.0 > 0, "birdie on a 400-yd hole should be positive SG, got \(eTee - 3.0)")
    }
    #endif
}
