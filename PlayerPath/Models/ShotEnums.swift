//
//  ShotEnums.swift
//  PlayerPath
//
//  Shared value types for shot-by-shot golf tracking (SchemaV30). Kept separate
//  from the `Shot` @Model so they can be referenced from pure helpers
//  (ShotRollup, ShotLieChain, ShotClubRecommender) and the entry UI without
//  pulling in SwiftData. All raw-string-backed for additive Firestore-wire
//  safety — same pattern as `Club`.
//

import Foundation

/// Where a golf shot is played FROM. Auto-chains from the previous shot's
/// `ShotOutcome` (see `ShotLieChain`); the player only corrects exceptions.
enum ShotLie: String, CaseIterable, Codable {
    case tee, fairway, rough, sand, fringe, green, recovery, water

    var displayName: String {
        switch self {
        case .tee:      return "Tee"
        case .fairway:  return "Fairway"
        case .rough:    return "Rough"
        case .sand:     return "Sand"
        case .fringe:   return "Fringe"
        case .green:    return "Green"
        case .recovery: return "Recovery"
        case .water:    return "Water"
        }
    }
}

/// Direction of a missed shot, derived from `ShotOutcome`. Feeds the free
/// miss-bias / approach-miss-pattern descriptive stats.
enum MissDir: String, Codable {
    case left, right

    var displayName: String { self == .left ? "Left" : "Right" }
}

/// Where a golf shot ENDED. Stored flat; the entry card offers only the
/// contextually-valid subset (see `ShotContext.outcomes`).
enum ShotOutcome: String, CaseIterable, Codable {
    case fairway        // tee shot found the fairway
    case missLeft       // missed left (tee or approach)
    case missRight      // missed right (tee or approach)
    case green          // on the green
    case short          // missed short
    case long           // missed long
    case fringe         // came to rest on the fringe
    case bunker         // came to rest in a bunker
    case holed          // in the hole
    case close          // chip/pitch on the green, close to the hole
    case on             // chip/pitch on the green

    var displayName: String {
        switch self {
        case .fairway:   return "Fairway"
        case .missLeft:  return "Left"
        case .missRight: return "Right"
        case .green:     return "Green"
        case .short:     return "Short"
        case .long:      return "Long"
        case .fringe:    return "Fringe"
        case .bunker:    return "Bunker"
        case .holed:     return "Holed"
        case .close:     return "Close"
        case .on:        return "On"
        }
    }

    /// Left/right miss direction, when applicable.
    var missDirection: MissDir? {
        switch self {
        case .missLeft:  return .left
        case .missRight: return .right
        default:         return nil
        }
    }

    /// True when the ball is now on the putting surface (or in the hole).
    var reachedGreen: Bool {
        switch self {
        case .green, .holed, .close, .on: return true
        default:                          return false
        }
    }

    /// True when the shot finished the hole.
    var isHoled: Bool { self == .holed }
}

/// The situation a shot is played in — drives which `ShotOutcome` buttons the
/// entry card offers. (Putting is a separate count stepper, not a context.)
enum ShotContext {
    case teeFull        // tee shot on a par 4 / 5
    case approach       // par-3 tee OR an approach to the green
    case aroundGreen    // greenside chip / pitch / bunker shot

    var outcomes: [ShotOutcome] {
        switch self {
        case .teeFull:     return [.fairway, .missLeft, .missRight]
        case .approach:    return [.green, .short, .long, .missLeft, .missRight, .fringe, .bunker, .holed]
        case .aroundGreen: return [.holed, .close, .on, .short]
        }
    }

    /// The entry context for a shot played from `lie` on a hole of `par`.
    /// Returns nil when the ball is on the green — that's putting, handled by
    /// the count stepper rather than result buttons. Without distance we lean on
    /// the lie: a greenside chip from rough still uses the `.approach` set (which
    /// includes `.holed`), losing only the Close/On proximity nuance.
    static func forLie(_ lie: ShotLie, par: Int) -> ShotContext? {
        switch lie {
        case .green:                       return nil
        case .tee:                                return par == 3 ? .approach : .teeFull
        case .fairway, .rough, .recovery, .water: return .approach
        case .sand, .fringe:                      return .aroundGreen
        }
    }
}
