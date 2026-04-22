import Foundation
import SwiftUI

// Centralized Notification.Name constants for app-wide events.

extension Notification.Name {
    static let gameCreated = Notification.Name("GameCreated")
    static let gameBecameLive = Notification.Name("GameBecameLive")
    static let gameEnded = Notification.Name("GameEnded")
    static let switchTab = Notification.Name("switchTab")
    static let presentVideoRecorder = Notification.Name("presentVideoRecorder")
    static let showAthleteSelection = Notification.Name("showAthleteSelection")
    static let switchAthlete = Notification.Name("switchAthlete")
    static let recordedHitResult = Notification.Name("recordedHitResult")
    static let videosManageOwnControls = Notification.Name("videosManageOwnControls")
    static let presentAddGame = Notification.Name("presentAddGame")
    static let presentFullscreenVideo = Notification.Name("presentFullscreenVideo")
    static let reactivateGame = Notification.Name("reactivateGame")
    static let presentSeasons = Notification.Name("presentSeasons")
    static let presentCoaches = Notification.Name("presentCoaches")
    static let presentCoachVideos = Notification.Name("presentCoachVideos")
    static let appWillEnterForeground = Notification.Name("AppWillEnterForeground")
    static let navigateToMorePractice = Notification.Name("navigateToMorePractice")
    static let navigateToMoreHighlights = Notification.Name("navigateToMoreHighlights")
    /// Coach: navigate to a specific shared folder. Post with `object: folderID` (String).
    static let navigateToCoachFolder = Notification.Name("navigateToCoachFolder")
    /// Athlete: navigate to a specific shared folder. Post with `object: folderID` (String).
    static let navigateToSharedFolder = Notification.Name("navigateToSharedFolder")
    /// Coach: open the invitations view.
    static let openCoachInvitations = Notification.Name("openCoachInvitations")
    /// Coach: switch to a specific coach tab. Post with `object: CoachTab.rawValue` (Int).
    static let switchCoachTab = Notification.Name("switchCoachTab")
    /// Show the subscription paywall (e.g., after accepting a coach invitation without Pro).
    static let showSubscriptionPaywall = Notification.Name("showSubscriptionPaywall")
    static let videoRecorded = Notification.Name("VideoRecorded")
    static let presentAddPractice = Notification.Name("presentAddPractice")
}
