//
//  GameAlertService.swift
//  PlayerPath
//
//  Schedules and cancels local notifications reminding users to end a live game.
//  Also provides a helper to detect stale live games for in-app prompts.
//

import Foundation
import UserNotifications

final class GameAlertService {

    static let shared = GameAlertService()

    /// A game is considered "stale" after this duration (default: 3.5 hours).
    static let staleDuration: TimeInterval = 3.5 * 3600

    private init() {}

    // MARK: - Notification Permission

    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Schedule / Cancel

    /// Schedules a local notification to fire after `staleDuration` if the game is never ended.
    func scheduleEndGameReminder(for game: Game) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "Still playing?"
            let opponentLabel = game.opponent.isEmpty ? "your game" : "vs \(game.opponent)"
            content.body = "Don't forget to end \(opponentLabel) when it's over."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: GameAlertService.staleDuration,
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: Self.notificationID(for: game),
                content: content,
                trigger: trigger
            )

            center.add(request) { error in
                if let error {
                    print("⚠️ GameAlertService: failed to schedule reminder — \(error)")
                }
            }
        }
    }

    /// Cancels the pending end-game reminder for the given game.
    func cancelEndGameReminder(for game: Game) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationID(for: game)])
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

    // MARK: - Helpers

    private static func notificationID(for game: Game) -> String {
        "stale-game-\(game.id.uuidString)"
    }
}
