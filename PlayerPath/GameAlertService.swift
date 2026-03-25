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
        let notifID = "stale-game-\(game.id.uuidString)"
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notifID])
    }

}
