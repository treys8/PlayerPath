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
    }

    // MARK: - Handle Quick Action

    func handleQuickAction(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = QuickAction(rawValue: shortcutItem.type) else {
            return false
        }

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
            NotificationCenter.default.post(name: .presentAddGame, object: nil)
            postSwitchTab(.games)

        case .addPractice:
            NotificationCenter.default.post(name: .presentAddPractice, object: nil)
            postSwitchTab(.more)

        case .viewStats:
            postSwitchTab(.stats)
        }

        // Clear the action after executing
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            selectedQuickAction = nil
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
