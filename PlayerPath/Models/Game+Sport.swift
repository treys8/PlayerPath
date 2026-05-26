//
//  Game+Sport.swift
//  PlayerPath
//
//  Sport-aware label helpers for Game. Golf rounds are played AT a course
//  or tournament, so user-facing rows read "at <venue>" instead of the
//  baseball/softball "vs <opponent>". Centralizing the prefix keeps every
//  render site (cards, thumbnails, search, share sheets, recorder chrome)
//  in sync.
//

import Foundation

extension Game {
    /// True when this game belongs to a golf season.
    var isGolf: Bool { season?.sport == .golf }

    /// "at" for golf, "vs" for baseball/softball.
    var opponentPrefix: String { isGolf ? "at" : "vs" }

    /// Full prefixed label, e.g. "at SCC" or "vs Rangers".
    var opponentLabel: String { "\(opponentPrefix) \(opponent)" }
}
