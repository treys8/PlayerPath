//
//  GameAlertService.swift
//  PlayerPath
//
//  Schedules and cancels local notifications reminding users to end a live game.
//  Also provides a helper to detect stale live games for in-app prompts.
//

import Foundation
@preconcurrency import UserNotifications

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
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            print("GameAlertService: notification authorization granted: \(granted)")
        } catch {
            print("⚠️ GameAlertService: notification authorization error — \(error)")
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
            print("GameAlertService: reminder already pending for game \(gameID)")
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
            print("⚠️ GameAlertService: failed to schedule reminder — \(error)")
        }
    }

    /// Cancels the pending end-game reminder for the given game.
    func cancelEndGameReminder(for game: Game) {
        let notifID = "stale-game-\(game.id.uuidString)"
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notifID])
    }

    // MARK: - Foreground Stale Check

    /// Returns live games whose `liveStartDate` exceeds `staleDuration` ago.
    func staleLiveGames(from games: [Game]) -> [Game] {
        let cutoff = Date().addingTimeInterval(-GameAlertService.staleDuration)
        return games.filter { game in
            guard game.isLive, let startDate = game.liveStartDate else { return false }
            return startDate < cutoff
        }
    }
}
