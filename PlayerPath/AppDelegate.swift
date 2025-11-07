//
//  AppDelegate.swift
//  PlayerPath
//
//  Created by Assistant on 10/30/25.
//

import UIKit
import UserNotifications
import StoreKit

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Set up push notifications
        setupPushNotifications(application)
        
        // Set up StoreKit transaction observer
        setupStoreKit()
        
        return true
    }
    
    // MARK: - Push Notifications Setup
    
    private func setupPushNotifications(_ application: UIApplication) {
        // Request notification permissions on app launch
        Task {
            await PushNotificationService.shared.requestAuthorization()
        }
    }
    
    // MARK: - StoreKit Setup
    
    private func setupStoreKit() {
        // This ensures transaction updates are processed even when the app launches
        Task {
            // Start listening for transaction updates immediately
            await PremiumFeatureManager().refreshStatus()
        }
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
        
        // Process the notification
        handleRemoteNotification(userInfo: userInfo)
        
        // Complete with appropriate result
        completionHandler(.newData)
    }
    
    private func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        // Handle different types of remote notifications
        if let notificationType = userInfo["type"] as? String {
            switch notificationType {
            case "premium_welcome":
                // Handle premium welcome notification
                break
            case "performance_insights":
                // Handle performance insights notification
                break
            case "cloud_backup_complete":
                // Handle cloud backup completion
                break
            case "game_reminder":
                // Handle game reminder
                break
            case "practice_reminder": 
                // Handle practice reminder
                break
            default:
                print("Unknown remote notification type: \(notificationType)")
            }
        }
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
        // Refresh premium status
        await PremiumFeatureManager().refreshStatus()
        
        // Check for pending cloud uploads (if premium)
        // Process any queued analytics (if premium)
        // Update notification badges
    }
}

// MARK: - Scene Configuration

extension AppDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

// MARK: - Scene Delegate

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    
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
        print("App launched from notification: \(actionIdentifier)")
        
        // You can post notifications to coordinate with your SwiftUI views
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            switch actionIdentifier {
            case "EXPLORE_FEATURES":
                NotificationCenter.default.post(name: .navigateToPremiumFeatures, object: nil)
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
        print("Handling URL: \(url)")
        
        // Example: playerpath://record/game/123
        // Example: playerpath://premium/upgrade
        // Example: playerpath://stats/athlete/456
    }
}

// MARK: - Background Tasks

extension AppDelegate {
    
    func registerBackgroundTasks() {
        // Register background tasks for premium features
        // This would be called during app initialization
        
        /*
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.playerpath.cloud-sync", using: nil) { task in
            self.handleCloudSyncBackgroundTask(task as! BGProcessingTask)
        }
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.playerpath.analytics-processing", using: nil) { task in
            self.handleAnalyticsBackgroundTask(task as! BGProcessingTask)
        }
        */
    }
    
    /*
    private func handleCloudSyncBackgroundTask(_ task: BGProcessingTask) {
        // Handle cloud synchronization in background for premium users
        let operation = CloudSyncOperation()
        
        task.expirationHandler = {
            operation.cancel()
        }
        
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }
        
        OperationQueue().addOperation(operation)
    }
    
    private func handleAnalyticsBackgroundTask(_ task: BGProcessingTask) {
        // Process analytics in background for premium users
        let operation = AnalyticsProcessingOperation()
        
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