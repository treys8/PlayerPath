//
//  Athlete+LiveActivity.swift
//  PlayerPath
//
//  The ONE answer to "what's in progress on this profile right now?" — shared by
//  the Live Now tab accessory, the Siri record intent, and every generic Record
//  button, so a clip recorded from anywhere lands in the live game or practice.
//

import SwiftData

extension Athlete {
    /// The in-progress game on this profile, scoped to the profile's sport
    /// (a seasonless game passes). Relationship arrays can still hold rows
    /// deleted by a sync remote-delete, an athlete delete cascade, or the
    /// sign-out wipe — reading any attribute of a deleted @Model traps
    /// (build 177/185) — so the athlete and each row are guarded first.
    var currentLiveGame: Game? {
        guard !isDeleted, modelContext != nil else { return nil }
        let sport = sportType
        return (games ?? []).first {
            !$0.isDeleted && $0.modelContext != nil && $0.isLive
                && ($0.season?.sport == nil || $0.season?.sport == sport)
        }
    }

    /// The in-progress practice (golf practice round or range session) on this
    /// profile, with the same guards and sport scoping as `currentLiveGame`.
    var currentLivePractice: Practice? {
        guard !isDeleted, modelContext != nil else { return nil }
        let sport = sportType
        return (practices ?? []).first {
            !$0.isDeleted && $0.modelContext != nil && $0.isLive
                && ($0.season?.sport == nil || $0.season?.sport == sport)
        }
    }
}
