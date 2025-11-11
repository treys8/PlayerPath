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
        
        // Configure Firebase when the app starts
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
    
    // MARK: - Push Notifications Setup
    
    private func setupPushNotifications(_ application: UIApplication) {
        // Request notification permissions on app launch and register for remote notifications on grant
        Task {
            let granted = await PushNotificationService.shared.requestAuthorization()
            appLog.info("Push authorization granted: \(granted, privacy: .public)")
            if granted {
                await MainActor.run {
                    application.registerForRemoteNotifications()
                }
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
        // Forward to notification service
        Task { @MainActor in
            PushNotificationService.shared.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Forward to notification service
        Task { @MainActor in
            PushNotificationService.shared.didFailToRegisterForRemoteNotifications(with: error)
        }
    }
    
    // Handle incoming push notifications when app is not running
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        // Process the notification and then call completion handler with a meaningful result
        Task {
            // Await any CloudKit processing; ignore return value if it's Void
            _ = await CloudKitManager.shared.handleRemoteNotification(userInfo)
            let handled = handleRemoteNotification(userInfo: userInfo)
            completionHandler(handled ? .newData : .noData)
        }
    }
    
    @discardableResult private func handleRemoteNotification(userInfo: [AnyHashable: Any]) -> Bool {
        var handled = false
        // Handle different types of remote notifications
        if let typeString = userInfo[RemoteNotificationKey.type] as? String,
           let type = RemoteNotificationType(rawValue: typeString) {
            switch type {
            case .performanceInsights:
                handled = true
            case .gameReminder:
                handled = true
            case .practiceReminder:
                handled = true
            }
        } else if let unknown = userInfo[RemoteNotificationKey.type] {
            appLog.info("Unknown remote notification type: \(String(describing: unknown), privacy: .public)")
        } else {
            appLog.info("Remote notification missing 'type' key")
        }
        return handled
    }
    
    // MARK: - Background Processing
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Perform background refresh tasks
        Task {
            await performBackgroundRefresh()
            completionHandler(.newData)
        }
    }
    
    private func performBackgroundRefresh() async {
        // Background refresh tasks can be added here later
        // For now, just a placeholder for future functionality
    }
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
        
        // You can post notifications to coordinate with your SwiftUI views
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            switch actionIdentifier {
            case "VIEW_STATS":
                if let athleteId = userInfo["athleteId"] as? String {
                    NotificationCenter.default.post(name: .navigateToStatistics, object: athleteId)
                }
            default:
                break
            }
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
        // Background tasks can be registered here for future functionality
        // This would be called during app initialization
        
        /*
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.playerpath.data-sync", using: nil) { task in
            self.handleDataSyncBackgroundTask(task as! BGProcessingTask)
        }
        */
    }
    
    /*
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

