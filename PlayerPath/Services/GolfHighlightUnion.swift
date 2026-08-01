//
//  GolfHighlightUnion.swift
//  PlayerPath
//
//  The canonical "golf highlight set". Golf carries TWO curation systems that
//  had drifted apart:
//
//   1. `VideoClip.isHighlight` — set manually (star button / bulk mark). Golf
//      never auto-sets it, because golf clips carry no PlayResult.
//   2. `HighlightReel` rows — created automatically by GolfScoreWriter when a
//      hole is scored birdie-or-better, bundling every clip filmed on that hole.
//
//  A surface reading only #1 (season recap, season detail, the game reel CTA)
//  reported "0 highlights" for a golf athlete whose whole season of birdies had
//  produced reels — and the post-round banner, which read only #2, disagreed
//  with the reel the game screen would build. Everything golf now unions both.
//
//  Baseball/softball is unaffected: it has no reels, so the union degenerates to
//  the `isHighlight` set those surfaces already used.
//

import Foundation
import SwiftData

/// All lookups are synchronous main-actor reads — no `await` between receiving a
/// model and reading it (feedback_swiftdata_model_access_across_await).
@MainActor
enum GolfHighlightUnion {

    /// Clip-ID strings (`VideoClip.id.uuidString`) referenced by the live
    /// `HighlightReel`s of the given games/practices.
    ///
    /// Fetches every reel flat and filters in memory on purpose: `#Predicate`
    /// can't equate optional UUIDs (`reel.gameID == someUUID` where the stored
    /// property is `UUID?`), so a predicate here would either fail to compile or
    /// trap at fetch (feedback_swiftdata_predicate_no_transforms). Reel counts are
    /// tiny — one row per birdie-or-better hole.
    static func reelClipIDStrings(gameIDs: Set<UUID>,
                                  practiceIDs: Set<UUID>,
                                  in context: ModelContext) -> Set<String> {
        guard !gameIDs.isEmpty || !practiceIDs.isEmpty else { return [] }
        let allReels: [HighlightReel]
        do {
            allReels = try context.fetch(FetchDescriptor<HighlightReel>())
        } catch {
            ErrorHandlerService.shared.handle(error, context: "GolfHighlightUnion.fetchReels", showAlert: false)
            return []
        }
        var ids: Set<String> = []
        for reel in allReels where !reel.isDeletedRemotely {
            if let gameID = reel.gameID, gameIDs.contains(gameID) {
                ids.formUnion(reel.clipIDs)
            } else if let practiceID = reel.practiceID, practiceIDs.contains(practiceID) {
                ids.formUnion(reel.clipIDs)
            }
        }
        return ids
    }

    /// The highlight set for ONE event (a golf round or practice): starred clips
    /// ∪ clips bundled into that event's birdie reels, chronological.
    ///
    /// `clips` is the event's own clip list, so the caller controls the scope and
    /// this never has to walk relationships across an await.
    static func highlightClips(from clips: [VideoClip],
                               gameID: UUID?,
                               practiceID: UUID?,
                               in context: ModelContext) -> [VideoClip] {
        let reelClipIDs = reelClipIDStrings(
            gameIDs: gameID.map { [$0] } ?? [],
            practiceIDs: practiceID.map { [$0] } ?? [],
            in: context
        )
        return chronological(clips, reelClipIDs: reelClipIDs)
    }

    /// The highlight set for a whole SEASON: starred clips ∪ every clip bundled
    /// into a birdie reel of any game or practice in that season, chronological.
    static func seasonHighlightClips(for season: Season, in context: ModelContext) -> [VideoClip] {
        let gameIDs = Set((season.games ?? []).map(\.id))
        let practiceIDs = Set((season.practices ?? []).map(\.id))
        let reelClipIDs = reelClipIDStrings(gameIDs: gameIDs, practiceIDs: practiceIDs, in: context)
        return chronological(season.videoClips ?? [], reelClipIDs: reelClipIDs)
    }

    /// Shared filter+sort so every surface produces a byte-identical ordered set —
    /// the reel cache is keyed on clip id + order, so a forked sort here would
    /// silently split one round's reel into two cache files.
    ///
    /// The id tiebreak matters: `sorted(by:)` is NOT stable, and clips can share a
    /// `createdAt` (bulk import stamps identical timestamps; a nil createdAt maps
    /// every clip to `.distantPast`). Without a total order the result would depend
    /// on input order — and the inputs genuinely differ, since the post-round banner
    /// replays an order frozen at round end while GameDetailView re-sorts live from
    /// the `game.videoClips` relationship, whose element order SwiftData doesn't
    /// guarantee. Both now share the `round_<id>` cache scope, so they must agree.
    private static func chronological(_ clips: [VideoClip], reelClipIDs: Set<String>) -> [VideoClip] {
        clips
            .filter { clip in
                guard !clip.isDeleted, !clip.isDeletedRemotely else { return false }
                return clip.isHighlight || reelClipIDs.contains(clip.id.uuidString)
            }
            .sorted { lhs, rhs in
                let l = lhs.createdAt ?? .distantPast
                let r = rhs.createdAt ?? .distantPast
                return l == r ? lhs.id.uuidString < rhs.id.uuidString : l < r
            }
    }
}
