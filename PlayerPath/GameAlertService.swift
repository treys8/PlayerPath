//
//  GameAlertService.swift
//  PlayerPath
//
//  Schedules and cancels local notifications reminding users to end a live game.
//

import Foundation
@preconcurrency import UserNotifications
import os

private let alertLog = Logger(subsystem: "com.playerpath.app", category: "GameAlert")

@MainActor
final class GameAlertService {

    static let shared = GameAlertService()

    /// A game is considered "stale" after this duration (default: 3.5 hours).
    nonisolated static let staleDuration: TimeInterval = 3.5 * 3600

    private init() {}

    // MARK: - Notification Permission

    func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            alertLog.warning("Failed to request notification authorization: \(error.localizedDescription)")
        }
    }

    // MARK: - Schedule / Cancel

    /// Schedules a local notification to fire after `staleDuration` if the game is never ended.
    func scheduleEndGameReminder(for game: Game) async {
        // Default true for users who haven't seen the toggle yet — preserves prior behavior.
        let staleEnabled = UserDefaults.standard.object(forKey: NotificationPrefKeys.staleGameReminders) as? Bool ?? true
        guard staleEnabled else { return }

        // Capture @MainActor-isolated model values before async boundary
        let opponentName = game.opponent
        let gameID = game.id

        let center = UNUserNotificationCenter.current()
        let notifID = "stale-game-\(gameID.uuidString)"

        // Check if a reminder is already pending for this game
        let pending = await center.pendingNotificationRequests()
        guard !pending.contains(where: { $0.identifier == notifID }) else {
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Still playing?"
        let opponentLabel = opponentName.isEmpty ? "your game" : "vs \(opponentName)"
        content.body = "Don't forget to end \(opponentLabel) when it's over."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: GameAlertService.staleDuration,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: notifID,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            alertLog.warning("Failed to schedule end-game reminder: \(error.localizedDescription)")
        }
    }

    /// Cancels the pending end-game reminder for the given game.
    func cancelEndGameReminder(for game: Game) {
        cancelEndGameReminder(forGameID: game.id)
    }

    /// ID-based variant for callers that have already deleted the `Game` model
    /// (or are about to). Building the identifier from a captured UUID avoids
    /// reading `game.id` on a SwiftData object that may no longer be valid.
    func cancelEndGameReminder(forGameID gameID: UUID) {
        let notifID = "stale-game-\(gameID.uuidString)"
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notifID])
    }

    /// Schedules a local notification to fire after `staleDuration` if a live
    /// golf practice (round or range session) is never ended. Mirrors
    /// `scheduleEndGameReminder`; shares the same settings toggle.
    /// Takes plain values, not the model — callers snapshot Practice fields
    /// synchronously BEFORE any await so a concurrent delete can't invalidate
    /// the model mid-flight (the build-177 crash class).
    func scheduleEndPracticeReminder(practiceID: UUID, isRound: Bool, course courseName: String?) async {
        // Default true for users who haven't seen the toggle yet — preserves prior behavior.
        let staleEnabled = UserDefaults.standard.object(forKey: NotificationPrefKeys.staleGameReminders) as? Bool ?? true
        guard staleEnabled else { return }

        let center = UNUserNotificationCenter.current()
        let notifID = "stale-practice-\(practiceID.uuidString)"

        // Check if a reminder is already pending for this practice
        let pending = await center.pendingNotificationRequests()
        guard !pending.contains(where: { $0.identifier == notifID }) else {
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        if isRound {
            content.title = "Still on the course?"
            let roundLabel = courseName.map { "your round at \($0)" } ?? "your practice round"
            content.body = "Don't forget to end \(roundLabel) when it's over."
        } else {
            content.title = "Still practicing?"
            content.body = "Don't forget to end your range session when you're done."
        }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: GameAlertService.staleDuration,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: notifID,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            alertLog.warning("Failed to schedule end-practice reminder: \(error.localizedDescription)")
        }
    }

    /// Cancels the pending end-practice reminder for the given practice.
    func cancelEndPracticeReminder(for practice: Practice) {
        cancelEndPracticeReminder(forID: practice.id)
    }

    /// ID-based overload for deletion paths where the model may already be
    /// detached from its context.
    func cancelEndPracticeReminder(forID practiceID: UUID) {
        let notifID = "stale-practice-\(practiceID.uuidString)"
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notifID])
    }

}
