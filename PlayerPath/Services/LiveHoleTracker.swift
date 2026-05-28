//
//  LiveHoleTracker.swift
//  PlayerPath
//
//  Pure-derivation helper that answers "what hole is the user currently on?"
//  for a live golf round. The current hole is the next unscored hole — i.e.
//  (max scored holeNumber) + 1, capped at total holes. Storing this as a
//  separate persisted field would invite drift between the pointer and the
//  actual HoleScore rows, so it's always computed.
//
//  Consumed by:
//    • ClipPersistenceService.saveClip — stamps VideoClip.holeNumber at save
//    • ScoreHoleSheet — picks the default hole when launched from a card
//    • LiveGameCard / Dashboard — labels the "Score Hole X" CTA
//

import Foundation

@MainActor
final class LiveHoleTracker {
    static let shared = LiveHoleTracker()
    private init() {}

    /// Returns the next-unscored hole number for a live golf tournament, or
    /// nil if the game is not live-and-golf. Capped at `holes` so a 19th tap
    /// can't escape the round.
    func currentHole(for game: Game?) -> Int? {
        guard let game else { return nil }
        guard game.isLive, game.season?.sport == .golf else { return nil }
        let totalHoles = game.holes ?? 18
        let scoredMax = (game.holeScores ?? []).map(\.holeNumber).max() ?? 0
        // Round is complete — no live hole. Returning the last hole here would
        // mis-tag any post-round clip onto hole `totalHoles` and flip its reel.
        guard scoredMax < totalHoles else { return nil }
        return scoredMax + 1
    }

    /// Practice-round next-unscored hole. Activated in PR3 by the PracticeType
    /// enum extension that introduces the `practice_round` raw value; range
    /// sessions and baseball practices return nil. Hole count is read from
    /// the Practice's `holes` field (PR3); falls back to 18 when unset to
    /// keep older / unmigrated rows usable.
    func currentHole(for practice: Practice?) -> Int? {
        guard let practice else { return nil }
        guard practice.isLive else { return nil }
        guard practice.practiceType == PracticeType.practiceRound.rawValue else { return nil }
        let totalHoles = practice.holes ?? 18
        let scoredMax = (practice.holeScores ?? []).map(\.holeNumber).max() ?? 0
        // Round is complete — no live hole (see game variant above).
        guard scoredMax < totalHoles else { return nil }
        return scoredMax + 1
    }
}
