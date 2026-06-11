//
//  HighlightReelBannerService.swift
//  PlayerPath
//
//  Holds the transient "post-event highlight reel" banner shown after a game or
//  practice ends. The banner makes the (already free, already-done) auto-curation
//  visible at the emotional peak: "PlayerPath found N highlights from today's …".
//  Plus users tap → watch the stitched reel; free users tap → paywall.
//
//  State only — the snapshot is built synchronously in UserMainFlow's
//  game/practice-ended observers (so a concurrent delete can't invalidate a
//  @Model mid-read) and rendered via HighlightReelBanner in the app-level overlay.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class HighlightReelBannerService {
    static let shared = HighlightReelBannerService()
    private init() {}

    /// The kind of event that just ended — drives the banner noun and is purely
    /// presentational (golf rounds are Games, so `.round` ≠ a separate model).
    enum EventKind {
        case game, round, practice

        var noun: String {
            switch self {
            case .game:     return "game"
            case .round:    return "round"
            case .practice: return "practice"
            }
        }
    }

    /// A value-type snapshot of an ended event's highlights. Holds clip *IDs*,
    /// not `VideoClip` objects: the summary outlives the synchronous observer
    /// (banner lives ~5s, tap may fire later), and retaining live `@Model`s across
    /// that window risks use-after-free. IDs resolve to clips at tap time.
    struct Summary: Identifiable, Equatable {
        let id: UUID            // event (game/practice) id — also the de-dupe key
        let eventKind: EventKind
        let scopeKey: String    // StitchedReelCache scope, e.g. "game_<uuid>"
        let title: String       // reel header, e.g. "vs Tigers · Jun 11"
        let clipIDs: [UUID]      // ordered (chronological) highlight clip ids
        let count: Int

        static func == (lhs: Summary, rhs: Summary) -> Bool { lhs.id == rhs.id }
    }

    private(set) var pending: Summary?
    private var lastFiredEventID: UUID?

    /// Present a banner for a just-ended event. No-ops if we already fired for
    /// this event id this session, so a `restart()` → `end()` cycle (or a
    /// duplicate notification delivery) can't re-nag for the same event.
    func present(_ summary: Summary) {
        guard summary.id != lastFiredEventID else { return }
        lastFiredEventID = summary.id
        pending = summary
    }

    /// Clear the banner — called on tap-through, the dismiss X, or auto-timeout.
    func dismiss() {
        pending = nil
    }
}
