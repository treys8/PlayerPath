//
//  OnboardingManager.swift
//  PlayerPath
//
//  Manages welcome tutorial and feature-tip state,
//  persisted to UserDefaults with per-user key scoping.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    // MARK: - Published State

    @Published var hasSeenWelcomeTutorial: Bool = false
    @Published var dismissedTips: Set<String> = []

    // MARK: - UserDefaults Keys

    /// Current user ID prefix for scoping keys. Empty string for legacy/unscoped usage.
    private var userPrefix: String = ""

    private func key(_ base: String) -> String {
        userPrefix.isEmpty ? base : "\(userPrefix)_\(base)"
    }

    private enum BaseKeys {
        static let hasSeenWelcomeTutorial = "hasSeenWelcomeTutorial"
        static let dismissedTips = "dismissedTips"
    }

    // MARK: - Initialization

    private init() {}

    /// Call this when the user signs in to scope all UserDefaults keys to their account.
    func configure(forUserID userID: String?) {
        userPrefix = userID ?? ""
        reloadState()
    }

    private func reloadState() {
        hasSeenWelcomeTutorial = UserDefaults.standard.bool(forKey: key(BaseKeys.hasSeenWelcomeTutorial))

        if let tipsData = UserDefaults.standard.array(forKey: key(BaseKeys.dismissedTips)) as? [String] {
            dismissedTips = Set(tipsData)
        } else {
            dismissedTips.removeAll()
        }
    }

    // MARK: - Welcome Tutorial

    func markWelcomeTutorialSeen() {
        hasSeenWelcomeTutorial = true
        UserDefaults.standard.set(true, forKey: key(BaseKeys.hasSeenWelcomeTutorial))
    }

    func resetWelcomeTutorial() {
        hasSeenWelcomeTutorial = false
        UserDefaults.standard.removeObject(forKey: key(BaseKeys.hasSeenWelcomeTutorial))
    }

    // MARK: - Feature Tips

    func shouldShowTip(_ tipID: String) -> Bool {
        !dismissedTips.contains(tipID)
    }

    func dismissTip(_ tipID: String) {
        dismissedTips.insert(tipID)
        UserDefaults.standard.set(Array(dismissedTips), forKey: key(BaseKeys.dismissedTips))
    }
}
