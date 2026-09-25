//
//  JournalEventReel.swift
//  PlayerPath
//
//  The reel behind a Journal game/practice card's "Watch Reel" button. Same
//  clip set, cache scope and threshold as the post-event banner (UserMainFlow)
//  and GameDetailView's Generate Reel, so every surface lands on ONE cached
//  stitched file per event instead of re-stitching.
//

import Foundation
import SwiftData

struct JournalEventReel: Identifiable {
    let clips: [VideoClip]
    /// StitchedReelCache scope — must match the banner / GameDetailView keys.
    let scopeKey: String
    let title: String
    var id: String { scopeKey }

    /// A reel needs at least two clips — one clip is just a clip.
    static let minimumClips = 2

    /// Cheap eligibility check for the card button: counts qualifying clips and
    /// stops at the threshold — no sort, no array building. Must accept exactly
    /// the clips `GolfHighlightUnion.highlightClips` would (live, not remotely
    /// deleted, starred or in one of the event's birdie reels), so the button
    /// never promises a reel `make` then refuses to build.
    static func hasReel(for entry: JournalEntry, reels: [HighlightReel]) -> Bool {
        let clips: [VideoClip]
        let reelClipIDs: Set<String>
        switch entry {
        case .game(let game):
            clips = game.videoClips ?? []
            reelClipIDs = game.season?.sport == .golf
                ? GolfHighlightUnion.reelClipIDStrings(gameIDs: [game.id], practiceIDs: [], reels: reels)
                : []
        case .practice(let practice):
            clips = practice.videoClips ?? []
            reelClipIDs = practice.season?.sport == .golf
                ? GolfHighlightUnion.reelClipIDStrings(gameIDs: [], practiceIDs: [practice.id], reels: reels)
                : []
        default:
            return false
        }
        var count = 0
        for clip in clips where !clip.isDeleted && !clip.isDeletedRemotely {
            guard clip.isHighlight || (!reelClipIDs.isEmpty && reelClipIDs.contains(clip.id.uuidString)) else { continue }
            count += 1
            if count >= minimumClips { return true }
        }
        return false
    }

    /// The reel for a `.game`/`.practice` entry, or nil when it's another entry
    /// type or has fewer than two highlight clips. Golf unions starred clips
    /// with the event's birdie-reel clips; baseball has no reel rows, so passing
    /// no reels reduces the union to its starred clips. `GolfHighlightUnion`
    /// owns the filter + ordering for both, so the clip order (part of the cache
    /// hash) is deterministic.
    static func make(for entry: JournalEntry, reels: [HighlightReel]) -> JournalEventReel? {
        switch entry {
        case .game(let game):
            let isGolf = game.season?.sport == .golf
            let clips = GolfHighlightUnion.highlightClips(
                from: game.videoClips ?? [],
                gameID: game.id,
                practiceID: nil,
                reels: isGolf ? reels : []
            )
            guard clips.count >= minimumClips else { return nil }
            return JournalEventReel(
                clips: clips,
                scopeKey: isGolf ? "round_\(game.id.uuidString)" : "game_\(game.id.uuidString)",
                title: title(for: game)
            )
        case .practice(let practice):
            let isGolf = practice.season?.sport == .golf
            let clips = GolfHighlightUnion.highlightClips(
                from: practice.videoClips ?? [],
                gameID: nil,
                practiceID: practice.id,
                reels: isGolf ? reels : []
            )
            guard clips.count >= minimumClips else { return nil }
            return JournalEventReel(
                clips: clips,
                scopeKey: isGolf ? "round_practice_\(practice.id.uuidString)" : "practice_\(practice.id.uuidString)",
                title: title(for: practice)
            )
        default:
            return nil
        }
    }

    /// "Tigers · Sep 3, 2026", or just the date when there's no opponent. The
    /// title is display/caption only; it isn't part of the cache key.
    private static func title(for game: Game) -> String {
        guard let date = game.date else { return game.opponent.isEmpty ? game.eventNoun : game.opponent }
        let d = DateFormatter.mediumDate.string(from: date)
        return game.opponent.isEmpty ? d : "\(game.opponent) · \(d)"
    }

    private static func title(for practice: Practice) -> String {
        let base = practice.course ?? (PracticeType(rawValue: practice.practiceType)?.displayName ?? "Practice")
        guard let date = practice.date else { return base }
        return "\(base) · \(DateFormatter.mediumDate.string(from: date))"
    }
}

/// Identity-stable tap target for a row's Watch Reel button. A closure
/// parameter would be a new value on every JournalView body pass, so SwiftUI
/// could never skip re-rendering a Plus user's game/practice rows. JournalView
/// creates one per view and refreshes `handler` in place each pass.
final class JournalReelTap {
    var handler: (JournalEntry) -> Void = { _ in }
    func play(_ entry: JournalEntry) { handler(entry) }
}
