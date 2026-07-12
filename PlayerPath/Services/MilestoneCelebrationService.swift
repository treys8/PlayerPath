//
//  MilestoneCelebrationService.swift
//  PlayerPath
//
//  Holds the transient "record stamp" banner shown the moment a game or round
//  completion earns a personal best / season first. Sibling to
//  HighlightReelBannerService — the two Tier-4 celebration surfaces share the
//  UserMainFlow overlay: gold reel banner ("PlayerPath found N highlights") and
//  this accent milestone stamp ("PERSONAL BEST"). When both fire for one game
//  end, the reel banner (tap-actionable) shows first and this stamp follows as a
//  coda once the reel banner clears.
//
//  State only — MilestoneReminderService.processGameEnd builds the value-type
//  Stamp synchronously (before its first await, so a concurrent delete can't
//  invalidate a @Model mid-read) from the top-ranked unseen milestone, and the
//  banner renders via MilestoneCelebrationBanner in the app-level overlay.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class MilestoneCelebrationService {
    static let shared = MilestoneCelebrationService()
    private init() {}

    /// A value-type snapshot of the milestone a completion earned. Plain strings
    /// only — `Milestone` is already a derived struct, and copying the fields we
    /// render keeps zero `@Model` references, so the stamp safely outlives the
    /// synchronous observer that built it (banner lives ~5s).
    struct Stamp: Identifiable, Equatable {
        let id: String          // milestone id — also the de-dupe key
        let kindLabel: String   // small-caps overline, e.g. "PERSONAL BEST"
        let title: String       // headline, e.g. "Lowest round of the season"
        let detail: String?     // optional context line, e.g. "vs Tigers · May 12"
        /// Golf rounds tint the stamp fairway-green; everything else terracotta.
        /// Carried explicitly because the UserMainFlow overlay sits outside the
        /// tab root's `.ppAccent(forGolf:)` scope, so `@Environment(\.ppAccent)`
        /// there would always resolve to the base accent.
        let isGolf: Bool

        static func == (lhs: Stamp, rhs: Stamp) -> Bool { lhs.id == rhs.id }
    }

    private(set) var pending: Stamp?
    private var lastFiredID: String?

    /// Present a stamp for a just-earned milestone. No-ops if we already fired for
    /// this milestone id this session, so a `restart()` → `end()` cycle (or a
    /// double completion) can't re-celebrate the same record.
    func present(_ stamp: Stamp) {
        guard stamp.id != lastFiredID else { return }
        lastFiredID = stamp.id
        pending = stamp
    }

    /// Clear the banner — called on tap, the dismiss X, or auto-timeout.
    func dismiss() {
        pending = nil
    }
}
