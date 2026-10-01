//
//  RecruitingFeature.swift
//  PlayerPath
//
//  Compile-time visibility switch for the recruiting profile.
//

import Foundation

/// Whether the recruiting profile is reachable from the UI.
///
/// **OFF as of 2026-10-01** — hidden again pending more research on the
/// feature. It was ON from 2026-08-09; the server half (serveRecruitingProfile,
/// recruitingViewDigest, recruitingLapseNotice) is held dark by its own switch,
/// `firebase/functions/src/recruitingSwitch.ts` (`internalState/recruiting`).
/// Turning recruiting back on means flipping BOTH: this flag (a resubmit) and
/// that doc's `enabled` field.
///
/// Keep this a compile-time constant. Do **not** drive it from Firestore
/// `appConfig` the way `AppUpdateManager` does: revealing a feature App Review
/// never saw is exactly what App Store guideline 2.3.1 prohibits. Turning it
/// off again is likewise a resubmit, not a remote switch — which is the point,
/// because a remote flip could strand a published page with no route to its
/// own unpublish control.
///
/// What this gates: the More-tab row, the Profile-tab row and its search
/// entry, the Edit Athlete section, and the Recruiting notification toggle.
///
/// What it deliberately does NOT gate: `MoreDestination.recruiting` and the
/// `recruiting_view` / `recruiting_offline` push routes into it. Those stay
/// wired in both states, so a profile published from an earlier build always
/// has a path back to the editor — which holds the only unpublish control —
/// rather than dead-ending.
enum RecruitingFeature {
    static let isEnabled = false
}
