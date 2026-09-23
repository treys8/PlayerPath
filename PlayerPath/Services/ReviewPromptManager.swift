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
        static let lastSessionDate = "ReviewPromptManager.lastSessionDate"
        static let completedGameCount = "ReviewPromptManager.completedGameCount"
    }

    // MARK: - Thresholds

    /// Minimum days between review prompts
    private let minimumDaysBetweenPrompts: Int = 60

    /// Minimum sessions before first prompt is eligible
    private let minimumSessionsBeforePrompt: Int = 5

    /// Minimum gap between activations that count as separate sessions.
    ///
    /// `scenePhase` returns to `.active` after *any* interruption: Control Center,
    /// the app switcher, an incoming notification banner, and — the reason this
    /// exists — every system alert the app raises itself (photo-library
    /// permission, notification permission, and the review prompt's own alert).
    /// Counting those meant a brand-new user could clear the 5-session bar in
    /// their first few minutes without ever having used the app across five
    /// sittings, which made `minimumSessionsBeforePrompt` effectively no gate.
    /// 30 minutes of inactivity is the usual definition of a session boundary.
    private let minimumSecondsBetweenSessions: TimeInterval = 30 * 60

    /// Game milestones that trigger a prompt check. Early entries (3, 5) catch
    /// new users while they're still forming an opinion; the ≥5-session and
    /// 60-day gates below keep the first actual prompt from being premature.
    private let gameMilestones: Set<Int> = [3, 5, 10, 25, 50, 100, 200, 500]

    // MARK: - State (backed by stored properties, synced to UserDefaults on set)

    private var _lastPromptDate: Date?
    private var _sessionCount: Int
    private var _lastSessionDate: Date?
    private var _completedGameCount: Int

    private var lastPromptDate: Date? {
        get { _lastPromptDate }
        set { _lastPromptDate = newValue; UserDefaults.standard.set(newValue, forKey: Keys.lastPromptDate) }
    }

    private var sessionCount: Int {
        get { _sessionCount }
        set { _sessionCount = newValue; UserDefaults.standard.set(newValue, forKey: Keys.sessionCount) }
    }

    private var lastSessionDate: Date? {
        get { _lastSessionDate }
        set { _lastSessionDate = newValue; UserDefaults.standard.set(newValue, forKey: Keys.lastSessionDate) }
    }

    private var completedGameCount: Int {
        get { _completedGameCount }
        set { _completedGameCount = newValue; UserDefaults.standard.set(newValue, forKey: Keys.completedGameCount) }
    }

    private init() {
        _lastPromptDate = UserDefaults.standard.object(forKey: Keys.lastPromptDate) as? Date
        _sessionCount = UserDefaults.standard.integer(forKey: Keys.sessionCount)
        _lastSessionDate = UserDefaults.standard.object(forKey: Keys.lastSessionDate) as? Date
        _completedGameCount = UserDefaults.standard.integer(forKey: Keys.completedGameCount)
    }

    // MARK: - Session Tracking

    /// Call when the app becomes active (scene phase -> .active).
    ///
    /// Safe to call on every activation — re-activations inside
    /// `minimumSecondsBetweenSessions` are ignored, so momentary interruptions
    /// (including the system alerts this app raises) don't inflate the count.
    func recordSession() {
        let now = Date()
        if let last = lastSessionDate, now.timeIntervalSince(last) < minimumSecondsBetweenSessions {
            #if DEBUG
            print("⭐ ReviewPromptManager: re-activation within session window, not counted")
            #endif
            return
        }

        lastSessionDate = now
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

        // All conditions met — request review.
        //
        // The cooldown is stamped only once the request is actually handed to
        // StoreKit. Without a foreground-active window scene nothing is shown,
        // and burning 60 days on a prompt the user never saw would silence the
        // next two months for free.
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            #if DEBUG
            print("⭐ ReviewPromptManager: no foreground-active scene, not requesting")
            #endif
            return
        }

        lastPromptDate = Date()

        #if DEBUG
        print("⭐ ReviewPromptManager: requesting App Store review")
        #endif

        AppStore.requestReview(in: windowScene)
    }
}
