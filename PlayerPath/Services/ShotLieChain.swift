//
//  ShotLieChain.swift
//  PlayerPath
//
//  Pure lie auto-chaining for shot-by-shot entry: the next shot's lie defaults
//  from the previous shot's outcome, so the golfer only corrects exceptions.
//  Kept as a free function (no SwiftData) so it's trivially unit-testable.
//

import Foundation

enum ShotLieChain {

    /// The lie the next shot is most likely played from, given this shot's
    /// outcome. A default the player can override via the tappable lie chip.
    static func nextLie(after outcome: ShotOutcome) -> ShotLie {
        switch outcome {
        case .fairway:                 return .fairway
        case .green, .close, .on:      return .green      // on the putting surface → putt
        case .missLeft, .missRight,
             .short, .long:            return .rough      // generic "missed it" lie
        case .fringe:                  return .fringe
        case .bunker:                  return .sand
        case .holed:                   return .green      // hole done; value unused
        }
    }
}
