import Foundation
import SwiftUI

// Centralized Notification.Name constants for app-wide events.

extension Notification.Name {
    static let gameCreated = Notification.Name("GameCreated")
    static let gameBecameLive = Notification.Name("GameBecameLive")
    static let gameEnded = Notification.Name("GameEnded")
    /// Posted by PracticeService.end() with `object: Practice` after the save
    /// succeeds. Only golf practices go live, so this is golf-only in practice.
    /// Mirrors `.gameEnded`; drives the post-event highlight-reel banner.
    static let practiceEnded = Notification.Name("PracticeEnded")
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
    static let presentCoachVideos = Notification.Name("presentCoachVideos")
    static let appWillEnterForeground = Notification.Name("AppWillEnterForeground")
    static let navigateToMorePractice = Notification.Name("navigateToMorePractice")
    static let navigateToMoreHighlights = Notification.Name("navigateToMoreHighlights")
    /// Coach: navigate to a specific shared folder. Post with `object: folderID` (String).
    static let navigateToCoachFolder = Notification.Name("navigateToCoachFolder")
    /// Athlete: navigate to a specific shared folder. Post with `object: folderID` (String).
    static let navigateToSharedFolder = Notification.Name("navigateToSharedFolder")
    /// Open the invitations surface, role-agnostic. The mounted tab bar handles it:
    /// CoachTabView pushes the coach invitations list; MainTabView switches the
    /// athlete to the Home tab where the AthleteInvitationsBanner lives.
    static let openInvitations = Notification.Name("openInvitations")
    /// Coach: switch to a specific coach tab. Post with `object: CoachTab.rawValue` (Int).
    static let switchCoachTab = Notification.Name("switchCoachTab")
    /// Show the subscription paywall (e.g., after accepting a coach invitation without Pro).
    static let showSubscriptionPaywall = Notification.Name("showSubscriptionPaywall")
    static let videoRecorded = Notification.Name("VideoRecorded")
    static let presentAddPractice = Notification.Name("presentAddPractice")
    /// Posted from DashboardView's golf-idle Quick Actions "New Practice"
    /// button. PracticesView listens and surfaces NewPracticeTypePicker
    /// (Range vs Practice Round). Golf athletes only — baseball ignores.
    static let presentGolfPracticePicker = Notification.Name("presentGolfPracticePicker")
    /// Posted alongside `navigateToMorePractice` so PracticesView can surface
    /// NewPracticeTypePicker on first appear even when it isn't yet in the
    /// hierarchy to hear `presentGolfPracticePicker` directly (cold mount /
    /// slow device). Sets a pending flag the view consumes in `.onAppear`.
    static let setGolfPickerPending = Notification.Name("setGolfPickerPending")
    /// Posted by PushNotificationService when a cloud-backup / upload-failed /
    /// storage-warning notification is tapped. Athlete navigates to More → Storage.
    static let navigateToCloudStorage = Notification.Name("navigateToCloudStorage")
    /// Posted when the weekly-summary local notification is tapped.
    static let navigateToWeeklySummary = Notification.Name("navigateToWeeklySummary")
    /// Posted by the GAME_REMINDER action / default tap with `object: gameId` (String).
    static let startRecordingForGame = Notification.Name("startRecordingForGame")
    /// Posted by the PRACTICE_REMINDER action / default tap with `object: practiceId` (String).
    static let startRecordingForPractice = Notification.Name("startRecordingForPractice")
}
