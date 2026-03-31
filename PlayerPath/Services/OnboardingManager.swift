//
//  OnboardingManager.swift
//  PlayerPath
//
//  Manages user onboarding state, feature discovery, and contextual tips
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    // MARK: - Published State

    @Published var hasCompletedInitialOnboarding: Bool
    @Published var hasSeenWelcomeTutorial: Bool
    @Published var hasRecordedFirstVideo: Bool
    @Published var hasCreatedFirstGame: Bool
    @Published var hasCreatedFirstPractice: Bool
    @Published var hasViewedStats: Bool
    @Published var hasUsedSearch: Bool
    @Published var hasExportedData: Bool
    @Published var hasUsedQuickActions: Bool
    @Published var hasInvitedCoach: Bool
    @Published var hasSeenCoachAnnouncement: Bool

    // Feature tips tracking
    @Published var dismissedTips: Set<String> = []
    @Published var currentTutorialStep: TutorialStep?
    @Published var showingFeatureDiscovery: Bool = false

    // MARK: - UserDefaults Keys

    /// Current user ID prefix for scoping keys. Empty string for legacy/unscoped usage.
    private var userPrefix: String = ""

    private func key(_ base: String) -> String {
        userPrefix.isEmpty ? base : "\(userPrefix)_\(base)"
    }

    private enum BaseKeys {
        static let hasCompletedInitialOnboarding = "hasCompletedInitialOnboarding"
        static let hasSeenWelcomeTutorial = "hasSeenWelcomeTutorial"
        static let hasRecordedFirstVideo = "hasRecordedFirstVideo"
        static let hasCreatedFirstGame = "hasCreatedFirstGame"
        static let hasCreatedFirstPractice = "hasCreatedFirstPractice"
        static let hasViewedStats = "hasViewedStats"
        static let hasUsedSearch = "hasUsedSearch"
        static let hasExportedData = "hasExportedData"
        static let hasUsedQuickActions = "hasUsedQuickActions"
        static let hasInvitedCoach = "hasInvitedCoach"
        static let hasSeenCoachAnnouncement = "hasSeenCoachAnnouncement"
        static let dismissedTips = "dismissedTips"
        static let onboardingVersion = "onboardingVersion"
    }

    private let currentOnboardingVersion = 1

    // MARK: - Initialization

    private init() {
        // Start with defaults; actual state is loaded when configure(forUserID:) is called
        self.hasCompletedInitialOnboarding = false
        self.hasSeenWelcomeTutorial = false
        self.hasRecordedFirstVideo = false
        self.hasCreatedFirstGame = false
        self.hasCreatedFirstPractice = false
        self.hasViewedStats = false
        self.hasUsedSearch = false
        self.hasExportedData = false
        self.hasUsedQuickActions = false
        self.hasInvitedCoach = false
        self.hasSeenCoachAnnouncement = false
    }

    /// Call this when the user signs in to scope all UserDefaults keys to their account.
    func configure(forUserID userID: String?) {
        userPrefix = userID ?? ""
        reloadState()
    }

    private func reloadState() {
        hasCompletedInitialOnboarding = UserDefaults.standard.bool(forKey: key(BaseKeys.hasCompletedInitialOnboarding))
        hasSeenWelcomeTutorial = UserDefaults.standard.bool(forKey: key(BaseKeys.hasSeenWelcomeTutorial))
        hasRecordedFirstVideo = UserDefaults.standard.bool(forKey: key(BaseKeys.hasRecordedFirstVideo))
        hasCreatedFirstGame = UserDefaults.standard.bool(forKey: key(BaseKeys.hasCreatedFirstGame))
        hasCreatedFirstPractice = UserDefaults.standard.bool(forKey: key(BaseKeys.hasCreatedFirstPractice))
        hasViewedStats = UserDefaults.standard.bool(forKey: key(BaseKeys.hasViewedStats))
        hasUsedSearch = UserDefaults.standard.bool(forKey: key(BaseKeys.hasUsedSearch))
        hasExportedData = UserDefaults.standard.bool(forKey: key(BaseKeys.hasExportedData))
        hasUsedQuickActions = UserDefaults.standard.bool(forKey: key(BaseKeys.hasUsedQuickActions))
        hasInvitedCoach = UserDefaults.standard.bool(forKey: key(BaseKeys.hasInvitedCoach))
        hasSeenCoachAnnouncement = UserDefaults.standard.bool(forKey: key(BaseKeys.hasSeenCoachAnnouncement))

        if let tipsData = UserDefaults.standard.array(forKey: key(BaseKeys.dismissedTips)) as? [String] {
            dismissedTips = Set(tipsData)
        } else {
            dismissedTips.removeAll()
        }

        let savedVersion = UserDefaults.standard.integer(forKey: key(BaseKeys.onboardingVersion))
        if savedVersion < currentOnboardingVersion {
            UserDefaults.standard.set(currentOnboardingVersion, forKey: key(BaseKeys.onboardingVersion))
        }
    }

    // MARK: - Milestone Tracking

    func markMilestoneComplete(_ milestone: OnboardingMilestone) {
        switch milestone {
        case .initialOnboarding:
            hasCompletedInitialOnboarding = true
            UserDefaults.standard.set(true, forKey: key(BaseKeys.hasCompletedInitialOnboarding))
        case .welcomeTutorial:
            hasSeenWelcomeTutorial = true
            UserDefaults.standard.set(true, forKey: key(BaseKeys.hasSeenWelcomeTutorial))
        case .firstVideo:
            hasRecordedFirstVideo = true
            UserDefaults.standard.set(true, forKey: key(BaseKeys.hasRecordedFirstVideo))
        case .firstGame:
            hasCreatedFirstGame = true
            UserDefaults.standard.set(true, forKey: key(BaseKeys.hasCreatedFirstGame))
        case .firstPractice:
            hasCreatedFirstPractice = true
            UserDefaults.standard.set(true, forKey: key(BaseKeys.hasCreatedFirstPractice))
        case .viewStats:
            hasViewedStats = true
            UserDefaults.standard.set(true, forKey: key(BaseKeys.hasViewedStats))
        case .useSearch:
            hasUsedSearch = true
            UserDefaults.standard.set(true, forKey: key(BaseKeys.hasUsedSearch))
        case .exportData:
            hasExportedData = true
            UserDefaults.standard.set(true, forKey: key(BaseKeys.hasExportedData))
        case .useQuickActions:
            hasUsedQuickActions = true
            UserDefaults.standard.set(true, forKey: key(BaseKeys.hasUsedQuickActions))
        case .inviteCoach:
            hasInvitedCoach = true
            UserDefaults.standard.set(true, forKey: key(BaseKeys.hasInvitedCoach))
        case .coachAnnouncement:
            hasSeenCoachAnnouncement = true
            UserDefaults.standard.set(true, forKey: key(BaseKeys.hasSeenCoachAnnouncement))
        }

        // Post notification for achievement tracking
        NotificationCenter.default.post(
            name: .onboardingMilestoneCompleted,
            object: milestone
        )
    }

    func hasMilestoneCompleted(_ milestone: OnboardingMilestone) -> Bool {
        switch milestone {
        case .initialOnboarding: return hasCompletedInitialOnboarding
        case .welcomeTutorial: return hasSeenWelcomeTutorial
        case .firstVideo: return hasRecordedFirstVideo
        case .firstGame: return hasCreatedFirstGame
        case .firstPractice: return hasCreatedFirstPractice
        case .viewStats: return hasViewedStats
        case .useSearch: return hasUsedSearch
        case .exportData: return hasExportedData
        case .useQuickActions: return hasUsedQuickActions
        case .inviteCoach: return hasInvitedCoach
        case .coachAnnouncement: return hasSeenCoachAnnouncement
        }
    }

    // MARK: - Feature Tips

    func shouldShowTip(_ tipID: String) -> Bool {
        return !dismissedTips.contains(tipID)
    }

    func dismissTip(_ tipID: String) {
        dismissedTips.insert(tipID)
        UserDefaults.standard.set(Array(dismissedTips), forKey: key(BaseKeys.dismissedTips))
    }

    func resetWelcomeTutorial() {
        hasSeenWelcomeTutorial = false
        UserDefaults.standard.removeObject(forKey: key(BaseKeys.hasSeenWelcomeTutorial))
    }

    // MARK: - Tutorial Flow

    func completeTutorial() {
        currentTutorialStep = nil
        markMilestoneComplete(.welcomeTutorial)
    }

    // MARK: - Coach Announcement

    var shouldShowCoachAnnouncement: Bool {
        AppFeatureFlags.isCoachEnabled
        && hasCompletedInitialOnboarding
        && !hasSeenCoachAnnouncement
    }

    // MARK: - Progress Tracking

    var onboardingProgress: Double {
        let milestones = OnboardingMilestone.allCases
        let completed = milestones.filter { hasMilestoneCompleted($0) }.count
        return Double(completed) / Double(milestones.count)
    }

    var completedMilestonesCount: Int {
        OnboardingMilestone.allCases.filter { hasMilestoneCompleted($0) }.count
    }

    var nextSuggestedAction: OnboardingMilestone? {
        // Return the first incomplete milestone
        OnboardingMilestone.allCases.first { !hasMilestoneCompleted($0) }
    }

}

// MARK: - Models

enum OnboardingMilestone: String, CaseIterable {
    case initialOnboarding
    case welcomeTutorial
    case firstVideo
    case firstGame
    case firstPractice
    case viewStats
    case useSearch
    case exportData
    case useQuickActions
    case inviteCoach
    case coachAnnouncement

    var title: String {
        switch self {
        case .initialOnboarding: return "Complete Setup"
        case .welcomeTutorial: return "Take the Tour"
        case .firstVideo: return "Record Your First Video"
        case .firstGame: return "Log Your First Game"
        case .firstPractice: return "Track a Practice"
        case .viewStats: return "Check Your Stats"
        case .useSearch: return "Search Your Videos"
        case .exportData: return "Export Your Data"
        case .useQuickActions: return "Use Quick Actions"
        case .inviteCoach: return "Connect with a Coach"
        case .coachAnnouncement: return "Coach Features Announcement"
        }
    }

    var description: String {
        switch self {
        case .initialOnboarding:
            return "Set up your athlete profile and get started"
        case .welcomeTutorial:
            return "Learn the basics with our quick tutorial"
        case .firstVideo:
            return "Capture your first swing on video"
        case .firstGame:
            return "Record game details and track performance"
        case .firstPractice:
            return "Document practice sessions"
        case .viewStats:
            return "Review your batting statistics"
        case .useSearch:
            return "Find specific videos quickly"
        case .exportData:
            return "Share your stats with coaches"
        case .useQuickActions:
            return "Access features from your home screen"
        case .inviteCoach:
            return "Collaborate with your coach"
        case .coachAnnouncement:
            return "Learn about coach sharing features"
        }
    }

    var icon: String {
        switch self {
        case .initialOnboarding: return "checkmark.circle.fill"
        case .welcomeTutorial: return "graduationcap.fill"
        case .firstVideo: return "video"
        case .firstGame: return "baseball.fill"
        case .firstPractice: return "figure.baseball"
        case .viewStats: return "chart.bar.fill"
        case .useSearch: return "magnifyingglass"
        case .exportData: return "square.and.arrow.up.fill"
        case .useQuickActions: return "hand.tap.fill"
        case .inviteCoach: return "person.2.fill"
        case .coachAnnouncement: return "megaphone.fill"
        }
    }
}

enum TipID {
    static let gamesAddButton = "tip_games_add"
    static let gameDetailStartGame = "tip_game_detail_start"
    static let videosRecord = "tip_videos_record"
    static let statsEmpty = "tip_stats_empty"
    static let dashboardGamesCard = "tip_dashboard_games_card"
}

enum Tutorial: CaseIterable {
    case welcome
    case videoRecording
    case gameTracking
    case statistics

    var steps: [TutorialStep] {
        switch self {
        case .welcome:
            return [
                .init(
                    title: "Welcome to PlayerPath",
                    description: "Track your baseball journey with video, stats, and insights",
                    imageName: "baseball.fill",
                    targetView: nil
                ),
                .init(
                    title: "Record Your Swings",
                    description: "Capture video of every at-bat to analyze your technique",
                    imageName: "video",
                    targetView: "videos_tab"
                ),
                .init(
                    title: "Track Your Games",
                    description: "Log game results and automatically calculate statistics",
                    imageName: "baseball.fill",
                    targetView: "games_tab"
                ),
                .init(
                    title: "Review Your Stats",
                    description: "See your progress with detailed statistics and charts",
                    imageName: "chart.bar.fill",
                    targetView: "stats_tab"
                )
            ]
        case .videoRecording:
            return [
                .init(
                    title: "Record a Video",
                    description: "Tap the record button to capture your swing",
                    imageName: "video.badge.plus",
                    targetView: "record_button"
                ),
                .init(
                    title: "Tag Your Plays",
                    description: "Mark each video with the result (single, double, etc.)",
                    imageName: "tag.fill",
                    targetView: "play_result_overlay"
                ),
                .init(
                    title: "Review & Analyze",
                    description: "Watch your videos in slow motion to improve",
                    imageName: "play.fill",
                    targetView: "video_player"
                )
            ]
        case .gameTracking:
            return [
                .init(
                    title: "Create a Game",
                    description: "Add game details like opponent and date",
                    imageName: "plus.circle.fill",
                    targetView: "add_game_button"
                ),
                .init(
                    title: "Record During the Game",
                    description: "Videos recorded during a game are automatically linked",
                    imageName: "video",
                    targetView: nil
                )
            ]
        case .statistics:
            return [
                .init(
                    title: "Your Statistics",
                    description: "All your stats are calculated automatically from your videos",
                    imageName: "chart.bar.fill",
                    targetView: "stats_view"
                ),
                .init(
                    title: "Export & Share",
                    description: "Generate reports to share with coaches and scouts",
                    imageName: "square.and.arrow.up.fill",
                    targetView: "export_button"
                )
            ]
        }
    }
}

struct TutorialStep: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let imageName: String
    let targetView: String? // Optional view to highlight

    init(title: String, description: String, imageName: String, targetView: String?) {
        // Derive a stable ID from the title so steps can be compared across accesses
        self.id = title
        self.title = title
        self.description = description
        self.imageName = imageName
        self.targetView = targetView
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let onboardingMilestoneCompleted = Notification.Name("onboardingMilestoneCompleted")
}
