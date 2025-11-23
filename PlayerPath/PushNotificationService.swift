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

@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()
    
    private let logger = Logger(subsystem: "PlayerPath", category: "PushNotificationService")
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Published Properties
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?
    @Published private(set) var isRegisteredForRemoteNotifications = false
    
    // Whether we should prompt the user to enable notifications (used by UI)
    var shouldPromptForNotifications: Bool {
        switch authorizationStatus {
        case .notDetermined, .denied:
            return true
        default:
            return false
        }
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
                ),
                UNNotificationAction(
                    identifier: "SHARE_STATS",
                    title: "Share",
                    options: []
                )
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
                ),
                UNNotificationAction(
                    identifier: "MANAGE_STORAGE",
                    title: "Manage Storage",
                    options: [.foreground]
                )
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
                ),
                UNNotificationAction(
                    identifier: "SNOOZE_REMINDER",
                    title: "Remind Later",
                    options: []
                )
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
                ),
                UNNotificationAction(
                    identifier: "RESCHEDULE_PRACTICE",
                    title: "Reschedule",
                    options: []
                )
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
                ),
                UNNotificationAction(
                    identifier: "SET_GOALS",
                    title: "Set Goals",
                    options: [.foreground]
                )
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
        let granted = await requestAuthorization()
        if granted {
            await registerForRemoteNotifications()
        }
        return granted
    }
    
    /// Presents a pre-permission rationale via a provided closure, then requests authorization and registers.
    /// - Parameters:
    ///   - presentRationale: A closure that presents UI explaining why notifications are useful. Call the provided completion with `true` to proceed or `false` to cancel.
    /// - Returns: true if authorization was granted.
    func promptWithRationale(presentRationale: @escaping (@escaping (Bool) -> Void) -> Void) async -> Bool {
        // If we shouldn't prompt (already authorized/limited), just proceed to ensure
        if !shouldPromptForNotifications {
            return await ensureAuthorizationAndRegister()
        }
        
        // Bridge async/await with callback-based rationale UI
        let shouldProceed: Bool = await withCheckedContinuation { continuation in
            presentRationale { proceed in
                continuation.resume(returning: proceed)
            }
        }
        
        guard shouldProceed else {
            logger.info("User declined notification rationale prompt")
            return false
        }
        
        let granted = await ensureAuthorizationAndRegister()
        if !granted && authorizationStatus == .denied {
            logger.info("Authorization denied; suggesting user to open settings")
        }
        return granted
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
        guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
            logger.warning("Cannot register for remote notifications - not authorized")
            return
        }
        
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
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
        if tokenChanged {
            Task {
                await sendTokenToServerWithRetry(tokenString)
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
        guard authorizationStatus == .authorized else { return }
        
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
        guard authorizationStatus == .authorized else { return }
        
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
    
    /// Schedule weekly performance summary
    func scheduleWeeklySummary(athleteId: String) async {
        guard authorizationStatus == .authorized else { return }
        
        // Schedule for every Sunday at 6 PM
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 18
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let success = await scheduleLocalNotification(
            identifier: "weekly_summary_\(athleteId)",
            title: "Weekly Performance Report 📊",
            body: "Check out your progress and see how you've improved this week!",
            categoryIdentifier: "WEEKLY_SUMMARY",
            userInfo: ["athleteId": athleteId, "type": "weekly_summary"],
            trigger: trigger
        )
        
        if success {
            logger.info("Scheduled weekly summary for athlete: \(athleteId)")
        }
    }
    
    /// Send immediate cloud backup completion notification
    func notifyCloudBackupComplete(videoCount: Int, totalSize: String) async {
        guard authorizationStatus == .authorized else { return }
        
        let title = "Cloud Backup Complete ☁️"
        let body = "\(videoCount) video\(videoCount == 1 ? "" : "s") (\(totalSize)) safely backed up to the cloud."
        
        let success = await scheduleLocalNotification(
            identifier: "cloud_backup_\(UUID().uuidString)",
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
    
    private func sendTokenToServerWithRetry(_ token: String, attempt: Int = 1, maxAttempts: Int = 3) async {
        let (success, shouldRetry) = await sendTokenToServer(token)
        
        if !success && shouldRetry && attempt < maxAttempts {
            // Exponential backoff: 2^attempt seconds
            let delay = pow(2.0, Double(attempt))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await sendTokenToServerWithRetry(token, attempt: attempt + 1, maxAttempts: maxAttempts)
        } else if !success && !shouldRetry {
            logger.error("Permanent failure sending token to server - will not retry")
        }
    }
    
    /// Returns (success, shouldRetry)
    private func sendTokenToServer(_ token: String) async -> (Bool, Bool) {
        // In a real app, you would send this token to your server
        // for push notification targeting
        #if DEBUG
        logger.info("Preparing to send device token to server")
        #endif

        
        // Example of what this might look like:
        /*
        let url = URL(string: "https://your-api.com/register-device")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "deviceToken": token,
            "platform": "ios",
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    logger.info("Successfully registered device token with server")
                    return (true, false)
                case 400...499:
                    // Client error - don't retry
                    logger.error("Client error registering token (status \(httpResponse.statusCode)) - will not retry")
                    return (false, false)
                case 500...599:
                    // Server error - retry
                    logger.error("Server error registering token (status \(httpResponse.statusCode)) - will retry")
                    return (false, true)
                default:
                    return (false, true)
                }
            }
            return (false, true)
        } catch {
            logger.error("Error sending device token to server: \(error.localizedDescription)")
            return (false, true) // Network errors are retryable
        }
        */
        
        // For now, return success as placeholder
        return (true, false)
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

