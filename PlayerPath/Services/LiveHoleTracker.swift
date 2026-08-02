//
//  LiveHoleTracker.swift
//  PlayerPath
//
//  Pure-derivation helpers for "which hole?" on a golf round. Storing either as
//  a persisted field would invite drift between the pointer and the actual
//  HoleScore rows, so both are always computed.
//
//  There are TWO questions here and they are NOT the same — collapsing them
//  mis-stamps clips:
//
//    • `nextUnscoredHole` — "which hole still needs a score?" = the first GAP in
//      1...total. Drives every "Score Hole N" CTA, so a skipped or deleted middle
//      hole is offered again rather than stranded.
//    • `currentPlayingHole` — "which hole is the golfer standing on?" = highest
//      scored + 1, because golf is played in order. Drives clip attribution only.
//      A gap behind the player (hole 3 deleted while they're on hole 10) must NOT
//      drag a hole-10 clip back onto hole 3.
//
//  Both ignore soft-deleted holes, and both return nil rather than clamping once
//  the round is complete — a finished round has no current hole, so the CTA hides
//  and a post-round clip can't mis-stamp onto the last hole.
//
//  Consumed by:
//    • nextUnscoredHole → LiveGameCard / Journal / Dashboard CTAs,
//      GameDetailView / PracticeDetailView, and the sheet each one opens
//    • currentPlayingHole → ClipPersistenceService.saveClip and
//      BulkVideoImportViewModel, via `currentHole(for:)`
//

import Foundation

@MainActor
final class LiveHoleTracker {
    static let shared = LiveHoleTracker()
    private init() {}

    /// First unscored hole in 1...totalHoles, or nil once every hole carries a
    /// live score.
    ///
    /// Soft-deleted (tombstoned) holes do NOT count as scored. `ShotByShotContent`
    /// deletes a synced hole by zeroing its score and flagging `isDeletedRemotely`
    /// until the next reconcile drops the row — counting those would both skip the
    /// deleted hole (it's still the max) and let a 0-stroke row poison any running
    /// total derived from the same list.
    ///
    /// Returns nil rather than clamping to the last hole: a finished round has no
    /// hole left to score, so the CTA hides instead of offering a tap that does
    /// nothing.
    static func nextUnscoredHole(holeScores: [HoleScore], totalHoles: Int) -> Int? {
        guard totalHoles > 0 else { return nil }
        let scored = Set(holeScores.lazy.filter { !$0.isDeletedRemotely }.map(\.holeNumber))
        return (1...totalHoles).first { !scored.contains($0) }
    }

    /// The hole the golfer is playing right now: one past the highest scored hole,
    /// or nil once the round is complete. Tombstoned holes are excluded, so
    /// deleting the hole you just scored puts you back ON it rather than skipping
    /// ahead.
    ///
    /// Deliberately NOT first-gap. A gap behind the player (they deleted hole 3
    /// while standing on hole 10) means hole 3 needs a score — it does not mean
    /// they walked backwards, and a clip filmed on 10 must not land in hole 3's
    /// reel.
    static func currentPlayingHole(holeScores: [HoleScore], totalHoles: Int) -> Int? {
        guard totalHoles > 0 else { return nil }
        let scoredMax = holeScores.lazy.filter { !$0.isDeletedRemotely }.map(\.holeNumber).max() ?? 0
        guard scoredMax < totalHoles else { return nil }
        return scoredMax + 1
    }

    // MARK: - Clip attribution

    /// The hole a clip captured right now belongs to, or nil if the game isn't
    /// live-and-golf (or is fully scored). The live gate is what makes this safe:
    /// a clip only inherits a hole while a round is actually running.
    func currentHole(for game: Game?) -> Int? {
        guard let game else { return nil }
        guard game.isLive, game.season?.sport == .golf else { return nil }
        return Self.currentPlayingHole(holeScores: game.holeScores ?? [],
                                       totalHoles: game.holes ?? 18)
    }

    /// Practice-round variant. Range sessions and baseball practices return nil —
    /// they have no holes to attribute to. Hole count falls back to 18 when unset
    /// so older / unmigrated rows stay usable.
    func currentHole(for practice: Practice?) -> Int? {
        guard let practice else { return nil }
        guard practice.isLive else { return nil }
        guard practice.practiceType == PracticeType.practiceRound.rawValue else { return nil }
        return Self.currentPlayingHole(holeScores: practice.holeScores ?? [],
                                       totalHoles: practice.holes ?? 18)
    }

    // MARK: - "Score Hole N" CTA

    /// The hole a live round's "Score Hole N" CTA should open, or nil when there's
    /// nothing left to score. Live-gated twins of `currentHole` so a card's label
    /// and the sheet it opens are always the same hole.
    func nextUnscoredHole(for game: Game?) -> Int? {
        guard let game else { return nil }
        guard game.isLive, game.season?.sport == .golf else { return nil }
        return Self.nextUnscoredHole(holeScores: game.holeScores ?? [],
                                     totalHoles: game.holes ?? 18)
    }

    func nextUnscoredHole(for practice: Practice?) -> Int? {
        guard let practice else { return nil }
        guard practice.isLive else { return nil }
        guard practice.practiceType == PracticeType.practiceRound.rawValue else { return nil }
        return Self.nextUnscoredHole(holeScores: practice.holeScores ?? [],
                                     totalHoles: practice.holes ?? 18)
    }
}
