//
//  QuickActionsManager.swift
//  PlayerPath
//
//  Manages iOS Home Screen Quick Actions (3D Touch / Haptic Touch shortcuts)
//

import UIKit
import SwiftUI
import Combine

@MainActor
final class QuickActionsManager: ObservableObject {
    static let shared = QuickActionsManager()

    @Published var selectedQuickAction: QuickAction?

    private init() {}

    // MARK: - Quick Action Types

    enum QuickAction: String {
        case recordVideo = "com.playerpath.recordVideo"
        case addGame = "com.playerpath.addGame"
        case addPractice = "com.playerpath.addPractice"
        case viewStats = "com.playerpath.viewStats"

        var title: String {
            switch self {
            case .recordVideo: return "Record Video"
            case .addGame: return "Add Game"
            case .addPractice: return "Add Practice"
            case .viewStats: return "View Statistics"
            }
        }

        var icon: UIApplicationShortcutIcon {
            switch self {
            case .recordVideo: return UIApplicationShortcutIcon(systemImageName: "video.badge.plus")
            case .addGame: return UIApplicationShortcutIcon(systemImageName: "baseball.fill")
            case .addPractice: return UIApplicationShortcutIcon(systemImageName: "figure.run")
            case .viewStats: return UIApplicationShortcutIcon(systemImageName: "chart.bar.fill")
            }
        }
    }

    // MARK: - Setup

    func setupQuickActions() {
        let shortcuts: [UIApplicationShortcutItem] = [
            UIApplicationShortcutItem(
                type: QuickAction.recordVideo.rawValue,
                localizedTitle: QuickAction.recordVideo.title,
                localizedSubtitle: nil,
                icon: QuickAction.recordVideo.icon,
                userInfo: nil
            ),
            UIApplicationShortcutItem(
                type: QuickAction.addGame.rawValue,
                localizedTitle: QuickAction.addGame.title,
                localizedSubtitle: nil,
                icon: QuickAction.addGame.icon,
                userInfo: nil
            ),
            UIApplicationShortcutItem(
                type: QuickAction.addPractice.rawValue,
                localizedTitle: QuickAction.addPractice.title,
                localizedSubtitle: nil,
                icon: QuickAction.addPractice.icon,
                userInfo: nil
            ),
            UIApplicationShortcutItem(
                type: QuickAction.viewStats.rawValue,
                localizedTitle: QuickAction.viewStats.title,
                localizedSubtitle: nil,
                icon: QuickAction.viewStats.icon,
                userInfo: nil
            )
        ]

        UIApplication.shared.shortcutItems = shortcuts
        print("✅ QuickActionsManager: Setup \(shortcuts.count) quick actions")
    }

    // MARK: - Handle Quick Action

    func handleQuickAction(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = QuickAction(rawValue: shortcutItem.type) else {
            print("⚠️ QuickActionsManager: Unknown quick action type: \(shortcutItem.type)")
            return false
        }

        print("🎯 QuickActionsManager: Handling quick action: \(action.title)")
        selectedQuickAction = action
        return true
    }

    // MARK: - Execute Action

    func executeAction(_ action: QuickAction) {
        switch action {
        case .recordVideo:
            NotificationCenter.default.post(name: .presentVideoRecorder, object: nil)
            postSwitchTab(.videos)

        case .addGame:
            NotificationCenter.default.post(name: Notification.Name("presentAddGame"), object: nil)
            postSwitchTab(.games)

        case .addPractice:
            NotificationCenter.default.post(name: Notification.Name("presentAddPractice"), object: nil)
            postSwitchTab(.practice)

        case .viewStats:
            postSwitchTab(.stats)
        }

        // Clear the action after executing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.selectedQuickAction = nil
        }
    }

    // MARK: - Clear

    func clearSelectedAction() {
        selectedQuickAction = nil
    }
}

// MARK: - App Delegate Integration

extension QuickActionsManager {
    /// Call this from SceneDelegate when app launches with a shortcut
    func handleLaunchShortcut(_ shortcutItem: UIApplicationShortcutItem?) {
        guard let shortcut = shortcutItem else { return }
        _ = handleQuickAction(shortcut)
    }
}
