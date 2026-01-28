//
//  AppDelegate.swift
//  PlayerPath
//
//  Created by Assistant on 10/30/25.
//

import UIKit
import UserNotifications
import FirebaseCore
import OSLog

private let appLog = Logger(subsystem: "com.playerpath.app", category: "AppDelegate")

class PlayerPathAppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Configure Firebase when the app starts (thread-safe with dispatch_once internally)
        if FirebaseApp.app() == nil {
            appLog.info("Configuring Firebase on launch")
            FirebaseApp.configure()
        } else {
            appLog.info("Firebase already configured")
        }
        
        // Set up push notifications
        setupPushNotifications(application)
        
        // Prepare for future background processing (no-op for now)
        registerBackgroundTasks()
        
        return true
    }
    
    // MARK: - Orientation Support
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // Allow all orientations for camera/video recording
        // SwiftUI views will override this to lock to portrait if needed
        return .allButUpsideDown
    }
    
    // MARK: - Push Notifications Setup
    
    private func setupPushNotifications(_ application: UIApplication) {
        // Request notification permissions on app launch and register for remote notifications on grant
        Task { @MainActor in
            let granted = await PushNotificationService.shared.requestAuthorization()
            appLog.info("Push authorization granted: \(granted, privacy: .public)")
            if granted {
                application.registerForRemoteNotifications()
            }
        }
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
    }
    
    // MARK: - Remote Notifications
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Forward to notification service (called on main thread by system)
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
                    await CloudKitManager.shared.handleRemoteNotification(userInfo)
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
        // Called when scene is about to enter foreground
        // Undo changes made on entering background
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Handle URL schemes if needed for deep linking
        for context in URLContexts {
            handleURL(context.url)
        }
    }
    
    private func handleNotificationLaunch(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        
        // Process notification launch
        appLog.info("App launched from notification: \(actionIdentifier, privacy: .public)")
        
        // Post notification for SwiftUI views to handle
        // Note: Use proper coordinator or deep link handler in production
        switch actionIdentifier {
        case "VIEW_STATS":
            if let athleteId = userInfo["athleteId"] as? String {
                NotificationCenter.default.post(name: .navigateToStatistics, object: athleteId)
            }
        default:
            break
        }
    }
    
    private func handleURL(_ url: URL) {
        // Handle custom URL schemes for deep linking
        appLog.info("Handling URL: \(url.absoluteString, privacy: .public)")
        
        // Example: playerpath://record/game/123  
        // Example: playerpath://stats/athlete/456
    }
}

// MARK: - Background Tasks

extension PlayerPathAppDelegate {
    
    func registerBackgroundTasks() {
        // Background tasks registration removed - not currently used
        // If needed in future, implement BGTaskScheduler with proper identifiers in Info.plist
    }
    
    /*
    // Removed - not currently implemented
    private func handleDataSyncBackgroundTask(_ task: BGProcessingTask) {
        // Handle data synchronization in background
        let operation = DataSyncOperation()
        
        task.expirationHandler = {
            operation.cancel()
        }
        
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }
        
        OperationQueue().addOperation(operation)
    }
    */
}

