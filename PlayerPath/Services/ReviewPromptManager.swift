//
//  ReviewPromptManager.swift
//  PlayerPath
//
//  Manages App Store review prompts with tasteful timing
//

import Foundation
import StoreKit
import UIKit

@MainActor
final class ReviewPromptManager {
    static let shared = ReviewPromptManager()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lastPromptDate = "ReviewPromptManager.lastPromptDate"
        static let sessionCount = "ReviewPromptManager.sessionCount"
        static let completedGameCount = "ReviewPromptManager.completedGameCount"
    }

    // MARK: - Thresholds

    /// Minimum days between review prompts
    private let minimumDaysBetweenPrompts: Int = 60

    /// Minimum sessions before first prompt is eligible
    private let minimumSessionsBeforePrompt: Int = 5

    /// Game milestones that trigger a prompt check (10th, 25th, 50th, 100th, ...)
    private let gameMilestones: Set<Int> = [10, 25, 50, 100, 200, 500]

    // MARK: - State (backed by stored properties, synced to UserDefaults on set)

    private var _lastPromptDate: Date?
    private var _sessionCount: Int
    private var _completedGameCount: Int

    private var lastPromptDate: Date? {
        get { _lastPromptDate }
        set { _lastPromptDate = newValue; UserDefaults.standard.set(newValue, forKey: Keys.lastPromptDate) }
    }

    private var sessionCount: Int {
        get { _sessionCount }
        set { _sessionCount = newValue; UserDefaults.standard.set(newValue, forKey: Keys.sessionCount) }
    }

    private var completedGameCount: Int {
        get { _completedGameCount }
        set { _completedGameCount = newValue; UserDefaults.standard.set(newValue, forKey: Keys.completedGameCount) }
    }

    private init() {
        _lastPromptDate = UserDefaults.standard.object(forKey: Keys.lastPromptDate) as? Date
        _sessionCount = UserDefaults.standard.integer(forKey: Keys.sessionCount)
        _completedGameCount = UserDefaults.standard.integer(forKey: Keys.completedGameCount)
    }

    // MARK: - Session Tracking

    /// Call when the app becomes active (scene phase -> .active).
    func recordSession() {
        sessionCount += 1
        #if DEBUG
        print("⭐ ReviewPromptManager: session #\(sessionCount)")
        #endif
    }

    // MARK: - Game Completion

    /// Call after a game is ended or marked complete.
    /// Increments the completed game counter and requests a review if a milestone is hit.
    func recordCompletedGame() {
        completedGameCount += 1
        let count = completedGameCount
        #if DEBUG
        print("⭐ ReviewPromptManager: completed game #\(count)")
        #endif

        if gameMilestones.contains(count) {
            requestReviewIfAppropriate()
        }
    }

    // MARK: - Review Request

    /// Checks all conditions and requests a review if appropriate.
    /// Safe to call liberally — it gates itself.
    func requestReviewIfAppropriate() {
        guard sessionCount >= minimumSessionsBeforePrompt else {
            #if DEBUG
            print("⭐ ReviewPromptManager: not enough sessions (\(sessionCount)/\(minimumSessionsBeforePrompt))")
            #endif
            return
        }

        if let lastDate = lastPromptDate {
            let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            guard daysSince >= minimumDaysBetweenPrompts else {
                #if DEBUG
                print("⭐ ReviewPromptManager: too soon since last prompt (\(daysSince)/\(minimumDaysBetweenPrompts) days)")
                #endif
                return
            }
        }

        // All conditions met — request review
        lastPromptDate = Date()

        #if DEBUG
        print("⭐ ReviewPromptManager: requesting App Store review")
        #endif

        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            AppStore.requestReview(in: windowScene)
        }
    }
}
