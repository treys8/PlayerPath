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

    // Feature tips tracking
    @Published var dismissedTips: Set<String> = []
    @Published var currentTutorialStep: TutorialStep?
    @Published var showingFeatureDiscovery: Bool = false

    // MARK: - UserDefaults Keys

    private enum Keys {
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
        static let dismissedTips = "dismissedTips"
        static let onboardingVersion = "onboardingVersion"
    }

    private let currentOnboardingVersion = 1

    // MARK: - Initialization

    private init() {
        // Load saved state
        self.hasCompletedInitialOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedInitialOnboarding)
        self.hasSeenWelcomeTutorial = UserDefaults.standard.bool(forKey: Keys.hasSeenWelcomeTutorial)
        self.hasRecordedFirstVideo = UserDefaults.standard.bool(forKey: Keys.hasRecordedFirstVideo)
        self.hasCreatedFirstGame = UserDefaults.standard.bool(forKey: Keys.hasCreatedFirstGame)
        self.hasCreatedFirstPractice = UserDefaults.standard.bool(forKey: Keys.hasCreatedFirstPractice)
        self.hasViewedStats = UserDefaults.standard.bool(forKey: Keys.hasViewedStats)
        self.hasUsedSearch = UserDefaults.standard.bool(forKey: Keys.hasUsedSearch)
        self.hasExportedData = UserDefaults.standard.bool(forKey: Keys.hasExportedData)
        self.hasUsedQuickActions = UserDefaults.standard.bool(forKey: Keys.hasUsedQuickActions)
        self.hasInvitedCoach = UserDefaults.standard.bool(forKey: Keys.hasInvitedCoach)

        if let tipsData = UserDefaults.standard.array(forKey: Keys.dismissedTips) as? [String] {
            self.dismissedTips = Set(tipsData)
        }

        // Check if onboarding needs reset due to version change
        let savedVersion = UserDefaults.standard.integer(forKey: Keys.onboardingVersion)
        if savedVersion < currentOnboardingVersion {
            // New onboarding version - could show "What's New" or reset certain tips
            UserDefaults.standard.set(currentOnboardingVersion, forKey: Keys.onboardingVersion)
        }
    }

    // MARK: - Milestone Tracking

    func markMilestoneComplete(_ milestone: OnboardingMilestone) {
        switch milestone {
        case .initialOnboarding:
            hasCompletedInitialOnboarding = true
            UserDefaults.standard.set(true, forKey: Keys.hasCompletedInitialOnboarding)
        case .welcomeTutorial:
            hasSeenWelcomeTutorial = true
            UserDefaults.standard.set(true, forKey: Keys.hasSeenWelcomeTutorial)
        case .firstVideo:
            hasRecordedFirstVideo = true
            UserDefaults.standard.set(true, forKey: Keys.hasRecordedFirstVideo)
        case .firstGame:
            hasCreatedFirstGame = true
            UserDefaults.standard.set(true, forKey: Keys.hasCreatedFirstGame)
        case .firstPractice:
            hasCreatedFirstPractice = true
            UserDefaults.standard.set(true, forKey: Keys.hasCreatedFirstPractice)
        case .viewStats:
            hasViewedStats = true
            UserDefaults.standard.set(true, forKey: Keys.hasViewedStats)
        case .useSearch:
            hasUsedSearch = true
            UserDefaults.standard.set(true, forKey: Keys.hasUsedSearch)
        case .exportData:
            hasExportedData = true
            UserDefaults.standard.set(true, forKey: Keys.hasExportedData)
        case .useQuickActions:
            hasUsedQuickActions = true
            UserDefaults.standard.set(true, forKey: Keys.hasUsedQuickActions)
        case .inviteCoach:
            hasInvitedCoach = true
            UserDefaults.standard.set(true, forKey: Keys.hasInvitedCoach)
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
        }
    }

    // MARK: - Feature Tips

    func shouldShowTip(_ tipID: String) -> Bool {
        return !dismissedTips.contains(tipID)
    }

    func dismissTip(_ tipID: String) {
        dismissedTips.insert(tipID)
        UserDefaults.standard.set(Array(dismissedTips), forKey: Keys.dismissedTips)
    }

    func resetTips() {
        dismissedTips.removeAll()
        UserDefaults.standard.removeObject(forKey: Keys.dismissedTips)
    }

    // MARK: - Tutorial Flow

    func startTutorial(_ tutorial: Tutorial) {
        currentTutorialStep = tutorial.steps.first
    }

    func nextTutorialStep() {
        guard let current = currentTutorialStep,
              let tutorial = Tutorial.allCases.first(where: { $0.steps.contains(current) }),
              let currentIndex = tutorial.steps.firstIndex(of: current) else {
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < tutorial.steps.count {
            currentTutorialStep = tutorial.steps[nextIndex]
        } else {
            completeTutorial()
        }
    }

    func skipTutorial() {
        currentTutorialStep = nil
    }

    func completeTutorial() {
        currentTutorialStep = nil
        markMilestoneComplete(.welcomeTutorial)
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

    // MARK: - Reset (for testing)

    func resetAllOnboarding() {
        hasCompletedInitialOnboarding = false
        hasSeenWelcomeTutorial = false
        hasRecordedFirstVideo = false
        hasCreatedFirstGame = false
        hasCreatedFirstPractice = false
        hasViewedStats = false
        hasUsedSearch = false
        hasExportedData = false
        hasUsedQuickActions = false
        hasInvitedCoach = false
        dismissedTips.removeAll()
        currentTutorialStep = nil

        UserDefaults.standard.removeObject(forKey: Keys.hasCompletedInitialOnboarding)
        UserDefaults.standard.removeObject(forKey: Keys.hasSeenWelcomeTutorial)
        UserDefaults.standard.removeObject(forKey: Keys.hasRecordedFirstVideo)
        UserDefaults.standard.removeObject(forKey: Keys.hasCreatedFirstGame)
        UserDefaults.standard.removeObject(forKey: Keys.hasCreatedFirstPractice)
        UserDefaults.standard.removeObject(forKey: Keys.hasViewedStats)
        UserDefaults.standard.removeObject(forKey: Keys.hasUsedSearch)
        UserDefaults.standard.removeObject(forKey: Keys.hasExportedData)
        UserDefaults.standard.removeObject(forKey: Keys.hasUsedQuickActions)
        UserDefaults.standard.removeObject(forKey: Keys.hasInvitedCoach)
        UserDefaults.standard.removeObject(forKey: Keys.dismissedTips)
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
        }
    }
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
    let id = UUID()
    let title: String
    let description: String
    let imageName: String
    let targetView: String? // Optional view to highlight

    static func == (lhs: TutorialStep, rhs: TutorialStep) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let onboardingMilestoneCompleted = Notification.Name("onboardingMilestoneCompleted")
}
