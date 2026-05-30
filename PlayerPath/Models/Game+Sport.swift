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

    /// User-facing noun for a single event. A golf game is a "Round" — the word
    /// "Tournament" now belongs to the multi-round `GolfTournament` container
    /// (SchemaV27), so a standalone golf game must NOT be called a tournament.
    /// Baseball/softball keep "Game". (Scoped down-payment on the A1 SportLabels
    /// refactor — route single-event label sites through this.)
    var eventNoun: String { isGolf ? "Round" : "Game" }

    /// Lowercased variant for mid-sentence copy ("delete this round").
    var eventNounLowercased: String { eventNoun.lowercased() }
}
