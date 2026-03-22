//
//  PushNotificationService.swift
//  PlayerPath
//
//  Created by Assistant on 10/30/25.
//

import Foundation
import UserNotifications
import SwiftUI
import Combine
import os.log
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()
    
    private let logger = Logger(subsystem: "PlayerPath", category: "PushNotificationService")
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Published Properties
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?
    @Published private(set) var isRegisteredForRemoteNotifications = false
    
    // Fix AI: Only .notDetermined warrants an in-app prompt.
    // .denied cannot be re-prompted — direct the user to Settings instead.
    var shouldPromptForNotifications: Bool {
        authorizationStatus == .notDetermined
    }

    var isPermissionDenied: Bool {
        authorizationStatus == .denied
    }

    /// Whether the user has granted any form of notification permission (full, provisional, or ephemeral).
    private var canScheduleNotifications: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }
    
    // MARK: - Notification Categories
    private let notificationCategories: Set<UNNotificationCategory> = [
        // Premium welcome category
        UNNotificationCategory(
            identifier: "PREMIUM_WELCOME",
            actions: [
                UNNotificationAction(
                    identifier: "EXPLORE_FEATURES",
                    title: "Explore Features",
                    options: [.foreground]
                )
            ],
            intentIdentifiers: []
        ),
        
        // Performance insights category
        UNNotificationCategory(
            identifier: "PERFORMANCE_INSIGHTS",
            actions: [
                UNNotificationAction(
                    identifier: "VIEW_STATS",
                    title: "View Stats",
                    options: [.foreground]
                )
                // Fix AK: SHARE_STATS removed — action was unhandled and presented dead UI
            ],
            intentIdentifiers: []
        ),
        
        // Cloud backup category
        UNNotificationCategory(
            identifier: "CLOUD_BACKUP",
            actions: [
                UNNotificationAction(
                    identifier: "VIEW_BACKUP",
                    title: "View Backup",
                    options: [.foreground]
                )
                // Fix AK: MANAGE_STORAGE removed — action was unhandled and presented dead UI
            ],
            intentIdentifiers: []
        ),
        
        // Game reminder category
        UNNotificationCategory(
            identifier: "GAME_REMINDER",
            actions: [
                UNNotificationAction(
                    identifier: "START_RECORDING",
                    title: "Start Recording",
                    options: [.foreground]
                )
                // Fix AK: SNOOZE_REMINDER removed — action was unhandled and presented dead UI
            ],
            intentIdentifiers: []
        ),
        
        // Practice reminder category
        UNNotificationCategory(
            identifier: "PRACTICE_REMINDER",
            actions: [
                UNNotificationAction(
                    identifier: "START_PRACTICE",
                    title: "Start Practice",
                    options: [.foreground]
                )
                // Fix AK: RESCHEDULE_PRACTICE removed — action was unhandled and presented dead UI
            ],
            intentIdentifiers: []
        ),
        
        // Weekly summary category
        UNNotificationCategory(
            identifier: "WEEKLY_SUMMARY",
            actions: [
                UNNotificationAction(
                    identifier: "VIEW_SUMMARY",
                    title: "View Summary",
                    options: [.foreground]
                )
                // Fix AK: SET_GOALS removed — action was unhandled and presented dead UI
            ],
            intentIdentifiers: []
        )
    ]
    
    // MARK: - Initialization
    override init() {
        super.init()
        Task {
            await setup()
        }
    }
    
    private func setup() async {
        // Set up notification categories
        notificationCenter.setNotificationCategories(notificationCategories)
        
        // Set delegate
        notificationCenter.delegate = self
        
        // Check current authorization status
        await updateAuthorizationStatus()
        
        logger.info("PushNotificationService initialized")
    }
    
    // MARK: - Authorization
    
    /// Prompts the user for notification permissions and updates internal state.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            await updateAuthorizationStatus()
            
            if granted {
                await registerForRemoteNotifications()
                logger.info("Notification authorization granted")
            } else {
                logger.warning("Notification authorization denied")
            }
            
            return granted
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Request authorization (if needed) and register for remote notifications in one step.
    /// - Returns: true if authorization is granted and registration was attempted.
    func ensureAuthorizationAndRegister() async -> Bool {
        // requestAuthorization() already calls registerForRemoteNotifications() when granted
        return await requestAuthorization()
    }
    
    /// If notifications are denied, open Settings; otherwise, no-op. Returns true if Settings was opened.
    @discardableResult
    func openSettingsIfDenied() -> Bool {
        if authorizationStatus == .denied {
            openNotificationSettings()
            return true
        }
        return false
    }
    
    private func updateAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        self.authorizationStatus = settings.authorizationStatus
        
        logger.info("Notification authorization status: \(self.authorizationStatus.rawValue)")
    }
    
    /// Registers with APNs if authorization allows; updates app state on AppDelegate callbacks.
    private func registerForRemoteNotifications() async {
        guard canScheduleNotifications else {
            logger.warning("Cannot register for remote notifications - not authorized")
            return
        }
        
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    /// Handle device token registration
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        // Check if token changed
        let previousToken = UserDefaults.standard.string(forKey: "deviceToken")
        let tokenChanged = previousToken != tokenString
        
        self.deviceToken = tokenString
        self.isRegisteredForRemoteNotifications = true
        
        Task { await updateAuthorizationStatus() }
        
        #if DEBUG
        logger.info("Registered for remote notifications (token \(tokenChanged ? "changed" : "unchanged"))")
        #else
        logger.info("Registered for remote notifications (token redacted, \(tokenChanged ? "changed" : "unchanged"))")
        #endif
        
        // Persist token for later use
        UserDefaults.standard.set(tokenString, forKey: "deviceToken")

        // Send token to server (only if changed or first time)
        // Pass the previous token directly — re-reading from UserDefaults inside the
        // async function would read the NEW token we just wrote above.
        if tokenChanged {
            Task {
                await sendTokenToServerWithRetry(tokenString, previousToken: previousToken)
            }
        }
    }
    
    /// Handle registration failure
    func didFailToRegisterForRemoteNotifications(with error: Error) {
        self.isRegisteredForRemoteNotifications = false
        logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // MARK: - Local Notifications
    
    /// Schedule a local notification
    func scheduleLocalNotification(
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String? = nil,
        userInfo: [String: Any] = [:],
        trigger: UNNotificationTrigger?
    ) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        
        if let categoryIdentifier = categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        do {
            try await notificationCenter.add(request)
            logger.info("Scheduled local notification: \(identifier)")
            return true
        } catch {
            logger.error("Failed to schedule local notification: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Cancel specific notifications
    func cancelNotifications(withIdentifiers identifiers: [String]) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        logger.info("Cancelled notifications: \(identifiers)")
    }
    
    /// Cancel all notifications
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        logger.info("Cancelled all notifications")
    }
    
    // MARK: - Specific Notification Types
    
    /// Schedule game reminder notification
    func scheduleGameReminder(
        gameId: String,
        opponent: String,
        scheduledTime: Date,
        reminderMinutes: Int = 30
    ) async {
        guard canScheduleNotifications else { return }
        
        let reminderDate = scheduledTime.addingTimeInterval(-TimeInterval(reminderMinutes * 60))
        guard reminderDate > Date() else { return }
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
            repeats: false
        )
        
        let success = await scheduleLocalNotification(
            identifier: "game_reminder_\(gameId)",
            title: "Game Starting Soon! ⚾",
            body: "Your game vs \(opponent) starts in \(reminderMinutes) minutes. Ready to record?",
            categoryIdentifier: "GAME_REMINDER",
            userInfo: ["gameId": gameId, "type": "game_reminder"],
            trigger: trigger
        )
        
        if success {
            logger.info("Scheduled game reminder for \(opponent)")
        }
    }
    
    /// Schedule practice reminder notification
    func schedulePracticeReminder(
        practiceId: String,
        practiceDate: Date,
        reminderMinutes: Int = 15
    ) async {
        guard canScheduleNotifications else { return }
        
        let reminderDate = practiceDate.addingTimeInterval(-TimeInterval(reminderMinutes * 60))
        guard reminderDate > Date() else { return }
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
            repeats: false
        )
        
        let success = await scheduleLocalNotification(
            identifier: "practice_reminder_\(practiceId)",
            title: "Practice Starting Soon! 🏃‍♂️",
            body: "Your practice starts in \(reminderMinutes) minutes. Don't forget to record key moments!",
            categoryIdentifier: "PRACTICE_REMINDER",
            userInfo: ["practiceId": practiceId, "type": "practice_reminder"],
            trigger: trigger
        )
        
        if success {
            logger.info("Scheduled practice reminder")
        }
    }
    
    /// Schedule weekly performance summary with real stats.
    /// Uses a one-shot trigger for next Sunday 6 PM so stats stay fresh
    /// when re-scheduled on each app foreground.
    func scheduleWeeklySummary(
        athleteId: String,
        gamesThisWeek: Int = 0,
        videosThisWeek: Int = 0,
        battingAverage: Double? = nil
    ) async {
        guard canScheduleNotifications else { return }

        // Cancel any existing weekly summary so we replace it with fresh stats
        cancelNotifications(withIdentifiers: ["weekly_summary_\(athleteId)"])

        // Find next Sunday at 6 PM
        let calendar = Calendar.current
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 18
        dateComponents.minute = 0

        guard let nextSunday = calendar.nextDate(after: Date(), matching: dateComponents, matchingPolicy: .nextTime) else {
            return
        }

        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextSunday)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

        // Build a data-aware message
        let body: String
        if gamesThisWeek > 0, let avg = battingAverage, avg > 0 {
            let avgFormatted = String(format: ".%03.0f", avg * 1000)
            body = "You logged \(gamesThisWeek) game\(gamesThisWeek == 1 ? "" : "s") this week. Batting \(avgFormatted). Keep it up!"
        } else if gamesThisWeek > 0 {
            body = "You logged \(gamesThisWeek) game\(gamesThisWeek == 1 ? "" : "s") this week. Open the app to see your stats!"
        } else if videosThisWeek > 0 {
            body = "You recorded \(videosThisWeek) video\(videosThisWeek == 1 ? "" : "s") this week. Review your clips and track your progress!"
        } else {
            body = "No games logged this week. Record your next game to keep your stats up to date!"
        }

        let success = await scheduleLocalNotification(
            identifier: "weekly_summary_\(athleteId)",
            title: "Your Week in Review",
            body: body,
            categoryIdentifier: "WEEKLY_SUMMARY",
            userInfo: ["athleteId": athleteId, "type": "weekly_summary"],
            trigger: trigger
        )

        if success {
            logger.info("Scheduled weekly summary for athlete: \(athleteId) (next Sunday)")
        }
    }
    
    /// Send immediate upload-complete notification (called after each successful upload)
    func notifyUploadComplete() async {
        guard canScheduleNotifications else { return }
        // Skip if app is in foreground — the upload UI already provides feedback
        guard UIApplication.shared.applicationState != .active else { return }
        _ = await scheduleLocalNotification(
            identifier: "upload_complete",
            title: "Upload Complete ☁️",
            body: "Your video has been successfully backed up to the cloud.",
            categoryIdentifier: "CLOUD_BACKUP",
            userInfo: ["type": "cloud_backup"],
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
    }

    /// Send immediate cloud backup completion notification
    func notifyCloudBackupComplete(videoCount: Int, totalSize: String) async {
        guard canScheduleNotifications else { return }
        // Skip if app is in foreground — the upload UI already provides feedback
        guard UIApplication.shared.applicationState != .active else { return }

        let title = "Cloud Backup Complete ☁️"
        let body = "\(videoCount) video\(videoCount == 1 ? "" : "s") (\(totalSize)) safely backed up to the cloud."

        let success = await scheduleLocalNotification(
            identifier: "cloud_backup_complete",
            title: title,
            body: body,
            categoryIdentifier: "CLOUD_BACKUP",
            userInfo: ["type": "cloud_backup", "videoCount": videoCount],
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        if success {
            logger.info("Sent cloud backup completion notification")
        }
    }
    
    // MARK: - Remote Notifications
    
    private func sendTokenToServerWithRetry(_ token: String, previousToken: String? = nil, attempt: Int = 1, maxAttempts: Int = 3) async {
        let (success, shouldRetry) = await sendTokenToServer(token, previousToken: previousToken)

        if !success && shouldRetry && attempt < maxAttempts {
            // Exponential backoff: 2^attempt seconds
            let delay = pow(2.0, Double(attempt))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await sendTokenToServerWithRetry(token, previousToken: previousToken, attempt: attempt + 1, maxAttempts: maxAttempts)
        } else if !success && !shouldRetry {
            logger.error("Permanent failure sending token to server - will not retry")
        }
    }

    /// Returns (success, shouldRetry)
    private func sendTokenToServer(_ token: String, previousToken: String? = nil) async -> (Bool, Bool) {
        // Store the APNs device token in the user's Firestore document so
        // future server-side push infrastructure can target this device.
        // Uses an array (deviceTokens) so multiple devices on the same account
        // all receive push notifications — arrayUnion prevents duplicates.
        guard let userID = Auth.auth().currentUser?.uid else {
            logger.warning("Cannot store device token — no authenticated user")
            return (false, false)
        }

        do {
            let db = Firestore.firestore()

            // If the token rotated, remove the old one first so stale tokens don't accumulate.
            if let old = previousToken, old != token {
                do {
                    try await db.collection(FC.users).document(userID).updateData([
                        "deviceTokens": FieldValue.arrayRemove([old])
                    ])
                } catch {
                    logger.warning("Failed to remove old device token: \(error.localizedDescription)")
                }
            }

            try await db.collection(FC.users).document(userID).setData([
                "deviceTokens": FieldValue.arrayUnion([token]),
                "deviceTokenUpdatedAt": FieldValue.serverTimestamp(),
                "platform": "ios"
            ], merge: true)
            logger.info("Stored device token in Firestore for user \(userID, privacy: .private)")
            return (true, false)
        } catch {
            logger.error("Failed to store device token: \(error.localizedDescription)")
            return (false, true)
        }
    }

    /// Removes this device's APNs token from Firestore. Call on sign-out so the
    /// device stops receiving push notifications for this account.
    func removeTokenFromServer() async {
        guard let token = UserDefaults.standard.string(forKey: "deviceToken"),
              let userID = Auth.auth().currentUser?.uid else { return }

        // Clear local token immediately so the next sign-in properly re-registers
        UserDefaults.standard.removeObject(forKey: "deviceToken")

        let db = Firestore.firestore()
        do {
            try await db.collection(FC.users).document(userID).updateData([
                "deviceTokens": FieldValue.arrayRemove([token])
            ])
            logger.info("Removed device token from Firestore for user \(userID, privacy: .private)")
        } catch {
            logger.error("Failed to remove device token from Firestore: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Notification Settings
    
    /// Open the app's notification settings (use when user previously denied permissions).
    func openNotificationSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    /// Check if specific notification types are enabled
    func checkNotificationSettings() async -> NotificationSettings {
        let settings = await notificationCenter.notificationSettings()
        
        return NotificationSettings(
            authorizationStatus: settings.authorizationStatus,
            soundSetting: settings.soundSetting,
            badgeSetting: settings.badgeSetting,
            alertSetting: settings.alertSetting,
            criticalAlertSetting: settings.criticalAlertSetting,
            providesAppNotificationSettings: settings.providesAppNotificationSettings,
            alertStyle: settings.alertStyle
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: UNUserNotificationCenterDelegate {
    
    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        logger.info("Received notification while app in foreground: \(notification.request.identifier)")
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .list, .sound, .badge])
    }
    
    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        
        logger.info("User interacted with notification: \(actionIdentifier)")
        
        handleNotificationResponse(actionIdentifier: actionIdentifier, userInfo: userInfo)
        
        completionHandler()
    }
    
    /// Fix AG: Called by SceneDelegate when the app is cold-launched from a notification tap.
    /// Forwards to the same routing logic used for foreground notification taps.
    func handleLaunchNotificationResponse(_ response: UNNotificationResponse) {
        handleNotificationResponse(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        )
    }

    /// Handle notification response actions
    private func handleNotificationResponse(actionIdentifier: String, userInfo: [AnyHashable: Any]) {
        // TODO: Replace NotificationCenter navigation with deep linking/coordinator pattern
        // Current implementation is a temporary solution
        
        switch actionIdentifier {
        case "EXPLORE_FEATURES":
            NotificationCenter.default.post(name: .navigateToPremiumFeatures, object: nil)
            
        case "VIEW_STATS":
            if let athleteId = userInfo["athleteId"] as? String {
                NotificationCenter.default.post(name: .navigateToStatistics, object: athleteId)
            } else {
                logger.warning("VIEW_STATS action missing athleteId")
            }
            
        case "VIEW_BACKUP":
            NotificationCenter.default.post(name: .navigateToCloudStorage, object: nil)
            
        case "START_RECORDING":
            if let gameId = userInfo["gameId"] as? String {
                NotificationCenter.default.post(name: .startRecordingForGame, object: gameId)
            } else {
                logger.warning("START_RECORDING action missing gameId")
            }
            
        case "START_PRACTICE":
            if let practiceId = userInfo["practiceId"] as? String {
                NotificationCenter.default.post(name: .startRecordingForPractice, object: practiceId)
            } else {
                logger.warning("START_PRACTICE action missing practiceId")
            }
            
        case "VIEW_SUMMARY":
            NotificationCenter.default.post(name: .navigateToWeeklySummary, object: nil)
            
        case UNNotificationDefaultActionIdentifier:
            // Handle default tap (open app)
            guard let notificationType = userInfo["type"] as? String else {
                logger.info("Default notification tap with no type specified")
                return
            }
            
            switch notificationType {
            case "game_reminder":
                if let gameId = userInfo["gameId"] as? String {
                    NotificationCenter.default.post(name: .startRecordingForGame, object: gameId)
                }
            case "practice_reminder":
                if let practiceId = userInfo["practiceId"] as? String {
                    NotificationCenter.default.post(name: .startRecordingForPractice, object: practiceId)
                }
            case "cloud_backup":
                NotificationCenter.default.post(name: .navigateToCloudStorage, object: nil)
            case "weekly_summary":
                // Fix AJ: route default tap to the same destination as the VIEW_SUMMARY action
                NotificationCenter.default.post(name: .navigateToWeeklySummary, object: nil)
            default:
                logger.info("Unhandled notification type: \(notificationType)")
            }
            
        default:
            logger.info("Unhandled notification action: \(actionIdentifier)")
        }
    }
}

// MARK: - Supporting Types

struct NotificationSettings {
    let authorizationStatus: UNAuthorizationStatus
    let soundSetting: UNNotificationSetting
    let badgeSetting: UNNotificationSetting
    let alertSetting: UNNotificationSetting
    let criticalAlertSetting: UNNotificationSetting
    let providesAppNotificationSettings: Bool
    let alertStyle: UNAlertStyle
    
    var isFullyEnabled: Bool {
        return authorizationStatus == .authorized &&
               soundSetting == .enabled &&
               alertSetting == .enabled
    }
}

// MARK: - Notification Names for Navigation

extension Notification.Name {
    static let navigateToPremiumFeatures = Notification.Name("navigateToPremiumFeatures")
    static let navigateToStatistics = Notification.Name("navigateToStatistics")
    static let navigateToCloudStorage = Notification.Name("navigateToCloudStorage")
    static let navigateToWeeklySummary = Notification.Name("navigateToWeeklySummary")
    static let startRecordingForGame = Notification.Name("startRecordingForGame")
    static let startRecordingForPractice = Notification.Name("startRecordingForPractice")
}

