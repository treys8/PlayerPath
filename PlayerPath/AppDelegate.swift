//
//  AppDelegate.swift
//  PlayerPath
//
//  Created by Assistant on 10/30/25.
//

import UIKit
import UserNotifications
import FirebaseCore
import FirebaseFirestore
import FirebaseAppCheck
import FirebaseMessaging
import BackgroundTasks
import OSLog

private let appLog = Logger(subsystem: "com.playerpath.app", category: "AppDelegate")

class PlayerPathAppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Configure App Check before Firebase — must be set before FirebaseApp.configure()
        // App Check is disabled until App Attest is properly configured in Firebase Console.
        // The debug provider only works in DEBUG builds; App Attest was returning 403 on
        // TestFlight/production builds, causing EXC_GUARD / XPC crashes.
        #if DEBUG
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        #endif

        // Configure Firebase when the app starts (thread-safe with dispatch_once internally)
        if FirebaseApp.app() == nil {
            appLog.info("Configuring Firebase on launch")
            FirebaseApp.configure()
            // Configure Firestore settings immediately — must happen before
            // any code accesses Firestore.firestore() elsewhere.
            let settings = FirestoreSettings()
            settings.cacheSettings = PersistentCacheSettings(
                sizeBytes: NSNumber(value: StorageConstants.urlCacheSizeBytes)
            )
            Firestore.firestore().settings = settings
        } else {
            appLog.info("Firebase already configured")
        }
        
        // Set up push notifications
        setupPushNotifications(application)

        // Prepare for future background processing (no-op for now)
        registerBackgroundTasks()

        // Clean up stale temp files from prior sessions (exports, orphaned imports)
        Task.detached(priority: .utility) {
            StorageManager.cleanupStaleExports()
            StorageManager.cleanupOrphanedImports()
        }

        return true
    }
    
    // MARK: - Orientation Support

    /// Set this to temporarily lock orientation (e.g. portrait for review screens).
    /// Always restore to `.allButUpsideDown` on dismiss.
    static var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return PlayerPathAppDelegate.orientationLock
    }
    
    // MARK: - Push Notifications Setup

    private func setupPushNotifications(_ application: UIApplication) {
        // Fix AE: Permission is no longer requested on cold launch — that produces a system
        // dialog before the user understands the app's value, leading to low opt-in rates.
        // PushNotificationService.init() already configures categories and the delegate.
        // The permission request is deferred to MainTabView.task, after onboarding completes.

        // Configure Firebase Cloud Messaging delegate for FCM token management
        Messaging.messaging().delegate = self

        appLog.info("Push notification categories and delegate configured via PushNotificationService.init()")
    }
    
    // MARK: - Remote Notification Keys & Types
    private enum RemoteNotificationKey {
        static let type = "type"
        static let athleteId = "athleteId"
    }
    
    private enum RemoteNotificationType: String {
        case performanceInsights = "performance_insights"
        case gameReminder = "game_reminder"
        case practiceReminder = "practice_reminder"
        // Coach/athlete notification types delivered via FCM
        case newVideo = "new_video"
        case coachComment = "coach_comment"
        case invitationReceived = "invitation_received"
        case invitationAccepted = "invitation_accepted"
        case accessRevoked = "access_revoked"
        case drillCard = "drill_card"
        case accessLapsed = "access_lapsed"
    }
    
    // MARK: - Remote Notifications
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Forward APNs token to Firebase Messaging so it can map to an FCM token
        Messaging.messaging().apnsToken = deviceToken

        // Forward to notification service for APNs token storage
        PushNotificationService.shared.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Forward to notification service (called on main thread by system)
        PushNotificationService.shared.didFailToRegisterForRemoteNotifications(with: error)
    }
    
    // Handle incoming push notifications when app is not running
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        // System gives 30 seconds max - use 25 second timeout with 5 second buffer
        Task { @MainActor in
            let handled = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
                // Task 1: Process the notification
                group.addTask { @MainActor in
                    return self.handleRemoteNotification(userInfo: userInfo)
                }
                
                // Task 2: Timeout protection (25 seconds)
                group.addTask {
                    try? await Task.sleep(for: .seconds(25))
                    await MainActor.run {
                        appLog.warning("Remote notification processing timed out after 25 seconds")
                    }
                    return false
                }
                
                // Return result from whichever completes first
                let result = await group.next() ?? false
                group.cancelAll()
                return result
            }
            
            completionHandler(handled ? .newData : .noData)
        }
    }
    
    @MainActor
    @discardableResult private func handleRemoteNotification(userInfo: [AnyHashable: Any]) -> Bool {
        // Handle different types of remote notifications
        if let typeString = userInfo[RemoteNotificationKey.type] as? String,
           let type = RemoteNotificationType(rawValue: typeString) {
            appLog.info("Handling remote notification type: \(type.rawValue, privacy: .public)")
            switch type {
            case .performanceInsights, .gameReminder, .practiceReminder:
                return true
            case .newVideo, .coachComment, .drillCard:
                // Coach notification — refresh in-app notification list
                NotificationCenter.default.post(name: .refreshActivityNotifications, object: nil)
                return true
            case .invitationReceived, .invitationAccepted:
                NotificationCenter.default.post(name: .refreshActivityNotifications, object: nil)
                return true
            case .accessRevoked, .accessLapsed:
                NotificationCenter.default.post(name: .refreshActivityNotifications, object: nil)
                return true
            }
        } else if let unknown = userInfo[RemoteNotificationKey.type] {
            appLog.info("Unknown remote notification type: \(String(describing: unknown), privacy: .public)")
        } else {
            appLog.info("Remote notification missing 'type' key")
        }
        return false
    }
    
    // MARK: - Background Processing
    
    // Note: application(_:performFetchWithCompletionHandler:) was deprecated in iOS 13
    // For background refresh, migrate to BGAppRefreshTask with BGTaskScheduler
    // See registerBackgroundTasks() method below for setup
}

// MARK: - Scene Configuration

extension PlayerPathAppDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

// MARK: - Scene Delegate

@MainActor class SceneDelegate: NSObject, UIWindowSceneDelegate {
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Handle scene connection

        // Check if launched from notification
        if let notificationResponse = connectionOptions.notificationResponse {
            handleNotificationLaunch(notificationResponse)
        }

        // Check if launched from quick action shortcut
        if let shortcutItem = connectionOptions.shortcutItem {
            handleQuickAction(shortcutItem)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        // Handle quick action when app is already running
        let handled = handleQuickAction(shortcutItem)
        completionHandler(handled)
    }

    @discardableResult
    private func handleQuickAction(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        // Forward to QuickActionsManager
        appLog.info("Handling quick action: \(shortcutItem.type, privacy: .public)")
        return QuickActionsManager.shared.handleQuickAction(shortcutItem)
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when scene transitions from background/inactive to active
        // Resume any paused tasks or refresh UI if needed
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        // Called when scene is about to transition from active to inactive
        // Pause ongoing tasks, disable timers, etc.
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called when scene enters background
        // Save data, release shared resources, store enough state information
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        NotificationCenter.default.post(name: .appWillEnterForeground, object: nil)
    }
    
    // Deep link URLs are handled by SwiftUI's .onOpenURL in PlayerPathApp.swift.
    // No scene(_:openURLContexts:) override needed — SwiftUI receives the URL directly.

    private func handleNotificationLaunch(_ response: UNNotificationResponse) {
        // Fix AG: Delegate all routing to PushNotificationService which has the full switch
        // covering every action identifier and notification type. Previously only VIEW_STATS
        // was handled here; all other cold-launch taps were silently dropped.
        appLog.info("App launched from notification: \(response.actionIdentifier, privacy: .public)")
        Task { @MainActor in
            PushNotificationService.shared.handleLaunchNotificationResponse(response)
        }
    }
    
}

// MARK: - Background Tasks

extension PlayerPathAppDelegate {

    func registerBackgroundTasks() {
        // Register video upload background task
        UploadQueueManager.registerBackgroundTasks()
        appLog.info("Background tasks registered")
    }
}

// MARK: - Firebase Cloud Messaging Delegate

extension PlayerPathAppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else {
            appLog.warning("FCM token refresh returned nil")
            return
        }
        appLog.info("FCM token received (length: \(fcmToken.count))")
        Task { @MainActor in
            PushNotificationService.shared.didReceiveFCMToken(fcmToken)
        }
    }
}

// MARK: - App Attest Provider Factory
/// Custom factory that creates `AppAttestProvider` instances for Firebase App Check.
/// `AppCheckDebugProviderFactory` is built-in, but there is no built-in factory
/// for App Attest — we must provide one ourselves.
private class PlayerPathAppAttestProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
        return AppAttestProvider(app: app)
    }
}


