//
//  CoachLiveSessionController.swift
//  PlayerPath
//
//  The ONE owner of the coach session recorder. CoachTabView presents the
//  cover; the Dashboard's live card and the iOS 26.1+ Live Now accessory both
//  ask through here, so two surfaces can never open two cameras for one session.
//

import SwiftUI

@MainActor
@Observable
final class CoachLiveSessionController {
    /// Drives the recorder fullScreenCover at the tab root. Non-nil iff it's up.
    var cameraContext: CoachSessionContext?

    /// Opens the recorder for the active session. No-op unless it's live.
    func recordIntoActiveSession() {
        guard let active = CoachSessionManager.shared.activeSession,
              active.status == .live else { return }
        recordInto(active)
    }

    /// Opens the recorder for a specific session, whatever its status — the
    /// folder's Record Clip resumes into its folder's active session as-is.
    func recordInto(_ session: CoachSession) {
        guard let id = session.id, !id.isEmpty else { return }
        cameraContext = CoachSessionContext(sessionID: id, session: session)
    }
}
