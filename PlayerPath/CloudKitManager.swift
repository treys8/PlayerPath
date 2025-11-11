//
//  CloudKitManager.swift
//  PlayerPath
//
//  Created by Assistant on 10/29/25.
//

import Foundation
import CloudKit
import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Notification Names
extension Notification.Name {
    static let userPreferencesDidChangeRemotely = Notification.Name("userPreferencesDidChangeRemotely")
}

// MARK: - CloudKit Manager Protocol
protocol CloudKitManagerProtocol {
    var isSignedInToiCloud: Bool { get }
    var cloudKitError: String? { get }
    var isCloudKitAvailable: Bool { get }
    var syncStatus: CloudKitManager.SyncStatus { get }
    var isInitialized: Bool { get }
    var cloudKitStatus: CloudKitManager.CloudKitStatus { get }
    
    func checkiCloudStatus()
    func fetchUserPreferences() async throws -> UserPreferences?
    func syncUserPreferences(_ preferences: UserPreferences) async throws
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async
    func registerContainer()
    func removeAllSubscriptions() async throws
    func refreshSubscriptions() async throws
}

@MainActor
@Observable
class CloudKitManager: CloudKitManagerProtocol {
    // Shared singleton instance
    static let shared = CloudKitManager()
    
    // Use private database for user data
    private let container = CKContainer.default()
    private var privateDatabase: CKDatabase { container.privateCloudDatabase }
    
    var isSignedInToiCloud = false
    var cloudKitError: String?
    var isCloudKitAvailable = false
    var syncStatus: SyncStatus = .idle
    var isInitialized = false
    var cloudKitStatus: CloudKitStatus = .initializing
    
    enum CloudKitStatus {
        case initializing
        case available
        case unavailable(reason: String)
        case syncing
        case syncFailed(error: CloudKitError)
    }
    
    enum SyncStatus {
        case idle
        case syncing
        case success
        case failed(CloudKitError)
    }
    
    enum CloudKitError: Error, LocalizedError {
        case networkError
        case authError
        case quotaExceeded
        case syncConflict(localDate: Date, remoteDate: Date)
        case partialFailure(failedRecords: [String])
        case rateLimited(retryAfter: TimeInterval?)
        case containerNotSetup
        case recordNotFound
        case unknownError(Error)
        
        var errorDescription: String? {
            switch self {
            case .networkError:
                return "No internet connection. Please check your network and try again."
            case .authError:
                return "Please sign in to iCloud in Settings to sync your preferences."
            case .quotaExceeded:
                return "Your iCloud storage is full. Please free up space to continue syncing."
            case .syncConflict(let localDate, let remoteDate):
                return "Your preferences were changed on another device. Local: \(localDate.formatted()), Remote: \(remoteDate.formatted())"
            case .partialFailure(let failedRecords):
                return "Some preferences failed to sync: \(failedRecords.joined(separator: ", "))"
            case .rateLimited(let retryAfter):
                if let retryAfter = retryAfter {
                    return "Too many requests. Please wait \(Int(retryAfter)) seconds before trying again."
                } else {
                    return "Too many requests. Please wait a moment before trying again."
                }
            case .containerNotSetup:
                return "iCloud sync is setting up. Please wait a moment and try again."
            case .recordNotFound:
                return "No saved preferences found in iCloud."
            case .unknownError(let error):
                return "Sync error: \(error.localizedDescription)"
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .networkError:
                return "Check your internet connection and try again."
            case .authError:
                return "Go to Settings > [Your Name] > iCloud and make sure you're signed in."
            case .quotaExceeded:
                return "Manage your iCloud storage in Settings > [Your Name] > iCloud > Manage Storage."
            case .syncConflict:
                return "You can choose to keep your local changes or download the remote version."
            case .partialFailure:
                return "Try syncing again. Some preferences may need individual attention."
            case .rateLimited:
                return "This is temporary. CloudKit will allow more requests soon."
            case .containerNotSetup:
                return "This happens on first setup. Wait 30 seconds and try again."
            case .recordNotFound:
                return "This is normal for first-time sync. Your preferences will be uploaded."
            case .unknownError:
                return "If this persists, try signing out and back into iCloud."
            }
        }
    }
    
    private init() {
        checkCloudKitAvailability()
        Task {
            await waitForInitialSetup()
        }
    }
    
    // MARK: - CloudKit Availability Check
    
    private func waitForInitialSetup() async {
        // Wait for iCloud status to be determined
        await checkiCloudStatusAsync()
        
        // Now set up subscriptions if available
        await setupSubscriptions()
        
        await MainActor.run {
            self.isInitialized = true
        }
        
        print("CloudKit: Initialization complete")
    }
    
    func checkCloudKitAvailability() {
        // CloudKit framework is available if we can create a container
        // This will only fail if CloudKit entitlements are missing
        self.isCloudKitAvailable = true
        checkiCloudStatus()
    }
    
    // Async version for initialization
    private func checkiCloudStatusAsync() async {
        do {
            // Use retry logic for account status check
            let status = try await retryCloudKitOperation {
                try await container.accountStatus()
            }
            
            // If account is available, try to access the database to register container
            if status == .available {
                // This call will register the container if it hasn't been registered yet
                // We'll perform a simple query to test database access
                _ = try await retryCloudKitOperation {
                    let query = CKQuery(recordType: "TestType", predicate: NSPredicate(value: false))
                    return try await privateDatabase.records(matching: query, resultsLimit: 1)
                }
                
                await MainActor.run {
                    self.isSignedInToiCloud = true
                    self.cloudKitError = nil
                    self.cloudKitStatus = .available
                    print("CloudKit: Successfully connected and container registered")
                }
            } else {
                await MainActor.run {
                    self.isSignedInToiCloud = false
                    let reason = self.getStatusMessage(for: status)
                    self.cloudKitError = reason
                    self.cloudKitStatus = .unavailable(reason: reason)
                    print("CloudKit: iCloud status - \(status)")
                }
            }
        } catch {
            await MainActor.run {
                self.isSignedInToiCloud = false
                
                let categorizedError = self.categorizeError(error)
                let errorMessage = categorizedError.localizedDescription
                
                self.cloudKitError = errorMessage
                self.cloudKitStatus = .unavailable(reason: errorMessage)
                print("CloudKit: Error - \(error)")
            }
        }
    }
    
    // MARK: - iCloud Account Status
    
    func checkiCloudStatus() {
        Task {
            do {
                // Use retry logic for account status check
                let status = try await retryCloudKitOperation {
                    try await container.accountStatus()
                }
                
                // If account is available, try to access the database to register container
                if status == .available {
                    // This call will register the container if it hasn't been registered yet
                    // We'll perform a simple query to test database access
                    _ = try await retryCloudKitOperation {
                        let query = CKQuery(recordType: "TestType", predicate: NSPredicate(value: false))
                        return try await privateDatabase.records(matching: query, resultsLimit: 1)
                    }
                    
                    await MainActor.run {
                        self.isSignedInToiCloud = true
                        self.cloudKitError = nil
                        self.cloudKitStatus = .available
                        print("CloudKit: Successfully connected and container registered")
                    }
                } else {
                    await MainActor.run {
                        self.isSignedInToiCloud = false
                        let reason = self.getStatusMessage(for: status)
                        self.cloudKitError = reason
                        self.cloudKitStatus = .unavailable(reason: reason)
                        print("CloudKit: iCloud status - \(status)")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSignedInToiCloud = false
                    
                    let categorizedError = self.categorizeError(error)
                    let errorMessage = categorizedError.localizedDescription
                    
                    self.cloudKitError = errorMessage
                    self.cloudKitStatus = .unavailable(reason: errorMessage)
                    print("CloudKit: Error - \(error)")
                }
            }
        }
    }
    
    private func getStatusMessage(for status: CKAccountStatus) -> String {
        switch status {
        case .couldNotDetermine:
            return "Could not determine iCloud status"
        case .noAccount:
            return "No iCloud account found. Please sign in to iCloud in Settings."
        case .restricted:
            return "iCloud account is restricted"
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable"
        case .available:
            return ""
        @unknown default:
            return "Unknown iCloud status"
        }
    }
    
    // MARK: - Error Handling
    
    private func retryCloudKitOperation<T>(_ operation: () async throws -> T, maxRetries: Int = 3) async throws -> T {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Don't retry certain errors
                if let ckError = error as? CKError {
                    switch ckError.code {
                    case .notAuthenticated, .permissionFailure, .quotaExceeded:
                        throw error // Don't retry auth or quota issues
                    case .requestRateLimited:
                        // For rate limiting, wait the specified time if available
                        if let retryAfter = ckError.retryAfterSeconds, attempt < maxRetries {
                            print("CloudKit: Rate limited, waiting \(retryAfter) seconds before retry \(attempt + 1)")
                            try await Task.sleep(for: .seconds(retryAfter))
                            continue
                        } else {
                            throw error
                        }
                    // Note: .invalidRequest is not available on this SDK; treat other non-transient errors as non-retryable.
                    case .invalidArguments, .serverRejectedRequest, .assetFileNotFound, .incompatibleVersion:
                        // Non-transient errors unlikely to succeed on retry
                        throw error
                    default:
                        break
                    }
                }
                
                // If this was the last attempt, throw the error
                if attempt == maxRetries {
                    throw error
                }
                
                // Exponential backoff: 1s, 2s, 4s
                let delay = pow(2.0, Double(attempt))
                print("CloudKit: Retry attempt \(attempt + 1) after \(delay)s delay due to: \(error.localizedDescription)")
                
                try await Task.sleep(for: .seconds(delay))
            }
        }
        
        // This should never be reached, but just in case
        throw lastError ?? CloudKitError.unknownError(NSError(domain: "RetryFailed", code: -1))
    }
    
    internal func categorizeError(_ error: Error) -> CloudKitError {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                return .networkError
            case .notAuthenticated, .permissionFailure:
                return .authError
            case .quotaExceeded:
                return .quotaExceeded
            case .requestRateLimited:
                let retryAfter = ckError.retryAfterSeconds
                return .rateLimited(retryAfter: retryAfter)
            case .unknownItem:
                return .recordNotFound
            case .partialFailure:
                // Extract failed record IDs from partial failure
                var failedRecords: [String] = []
                if let partialErrors = ckError.partialErrorsByItemID {
                    failedRecords = partialErrors.keys.compactMap { key in
                        if let recordID = key as? CKRecord.ID {
                            return recordID.recordName
                        }
                        return nil
                    }
                }
                return .partialFailure(failedRecords: failedRecords)
            case .badContainer, .missingEntitlement:
                return .containerNotSetup
            default:
                return .unknownError(error)
            }
        }
        
        // Handle URL errors (network issues)
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return .networkError
            default:
                return .unknownError(error)
            }
        }
        
        return .unknownError(error)
    }
    
    // MARK: - CloudKit Subscriptions
    
    private func setupSubscriptions() async {
        print("CloudKit: Setting up subscriptions (requesting remote notification authorization)")
        registerForRemoteNotifications()
        await createUserPreferencesSubscription()
        print("CloudKit: Subscriptions setup completed")
    }
    
    @MainActor
    private func registerForRemoteNotifications() {
        #if canImport(UIKit)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                // Already authorized or provisionally allowed
                DispatchQueue.main.async {
                    if !UIApplication.shared.isRegisteredForRemoteNotifications {
                        UIApplication.shared.registerForRemoteNotifications()
                        print("CloudKit: Registered for remote notifications (already authorized)")
                    } else {
                        print("CloudKit: Already registered for remote notifications")
                    }
                }
            case .denied:
                print("CloudKit: Notification authorization denied; not registering for remote notifications")
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        print("CloudKit: Notification authorization error: \(error.localizedDescription)")
                    }
                    print("CloudKit: Notification authorization granted: \(granted)")
                    if granted {
                        DispatchQueue.main.async {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    } else {
                        print("CloudKit: Remote notifications not granted; silent pushes may not be delivered")
                    }
                }
            @unknown default:
                print("CloudKit: Unknown authorization status; not registering")
            }
        }
        #else
        print("CloudKit: Remote notifications not supported on this platform")
        #endif
    }
    
    private func createUserPreferencesSubscription() async {
        print("CloudKit: Ensuring user preferences subscription exists")
        guard isCloudKitAvailable && isSignedInToiCloud else {
            print("CloudKit: Skipping subscription creation (available=\(isCloudKitAvailable), signedIn=\(isSignedInToiCloud))")
            return
        }
        
        do {
            // Check if subscription already exists with retry logic
            let existingSubscriptions = try await retryCloudKitOperation {
                try await privateDatabase.allSubscriptions()
            }
            
            let subscriptionID = "UserPreferencesSubscription"
            
            if existingSubscriptions.contains(where: { $0.subscriptionID == subscriptionID }) {
                print("CloudKit: User preferences subscription already exists")
                return
            }
            
            // Create a query subscription for UserPreferences changes
            let subscription = CKQuerySubscription(
                recordType: "UserPreferences",
                predicate: NSPredicate(value: true),
                subscriptionID: subscriptionID,
                options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
            )
            
            // Configure notification info
            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            notificationInfo.shouldBadge = false
            subscription.notificationInfo = notificationInfo
            
            // Save the subscription with retry logic
            _ = try await retryCloudKitOperation {
                try await privateDatabase.save(subscription)
            }
            
            print("CloudKit: User preferences subscription created successfully")
            
        } catch {
            print("CloudKit: Failed to create subscription: \(error)")
        }
    }
    
    // MARK: - Subscription Management
    
    func removeAllSubscriptions() async throws {
        guard isCloudKitAvailable && isSignedInToiCloud else {
            throw CloudKitError.authError
        }
        
        do {
            let subscriptions = try await retryCloudKitOperation {
                try await privateDatabase.allSubscriptions()
            }
            
            for subscription in subscriptions {
                _ = try await retryCloudKitOperation {
                    try await privateDatabase.deleteSubscription(withID: subscription.subscriptionID)
                }
                print("CloudKit: Deleted subscription: \(subscription.subscriptionID)")
            }
            
            print("CloudKit: All subscriptions removed")
        } catch {
            print("CloudKit: Failed to remove subscriptions: \(error)")
            throw categorizeError(error)
        }
    }
    
    func refreshSubscriptions() async throws {
        guard isCloudKitAvailable && isSignedInToiCloud else {
            throw CloudKitError.authError
        }
        
        do {
            // Remove existing subscriptions first
            try await removeAllSubscriptions()
            
            // Recreate the user preferences subscription
            await createUserPreferencesSubscription()
            
            print("CloudKit: Subscriptions refreshed successfully")
        } catch {
            print("CloudKit: Failed to refresh subscriptions: \(error)")
            throw error
        }
    }
    
    // Handle remote notifications
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return
        }
        
        switch notification.notificationType {
        case .query:
            if let queryNotification = notification as? CKQueryNotification {
                print("CloudKit: Received query notification (subscriptionID: \(queryNotification.subscriptionID ?? "nil"))")
                await handleQueryNotification(queryNotification)
            }
        case .database:
            if let databaseNotification = notification as? CKDatabaseNotification {
                print("CloudKit: Received database notification (subscriptionID: \(databaseNotification.subscriptionID ?? "nil"))")
                await handleDatabaseNotification(databaseNotification)
            }
        default:
            print("CloudKit: Received unknown notification type")
        }
    }
    
    private func handleQueryNotification(_ notification: CKQueryNotification) async {
        print("CloudKit: Received query notification for \(notification.recordID?.recordName ?? "unknown")")
        
        // Handle UserPreferences changes
        if notification.subscriptionID == "UserPreferencesSubscription" {
            await MainActor.run {
                // Notify the app that preferences may have changed
                NotificationCenter.default.post(name: .userPreferencesDidChangeRemotely, object: nil)
            }
        }
    }
    
    private func handleDatabaseNotification(_ notification: CKDatabaseNotification) async {
        print("CloudKit: Received database notification")
        // Handle database-wide changes if needed
    }
    
    func registerContainer() {
        Task {
            do {
                print("CloudKit: Attempting to register container...")
                
                // Try to perform a simple query to test database access
                let query = CKQuery(recordType: "TestType", predicate: NSPredicate(value: false))
                _ = try await privateDatabase.records(matching: query, resultsLimit: 1)
                
                await MainActor.run {
                    self.cloudKitError = "Container registration test completed successfully!"
                    self.checkiCloudStatus() // Recheck status after registration
                }
            } catch {
                await MainActor.run {
                    self.cloudKitError = "Container registration failed: \(error.localizedDescription)"
                    print("CloudKit: Registration error - \(error)")
                }
            }
        }
    }
}

// MARK: - CloudKit Record Types

extension CloudKitManager {
    // MARK: - User Preferences Sync
    
    func fetchUserPreferences() async throws -> UserPreferences? {
        guard isCloudKitAvailable && isSignedInToiCloud else {
            throw CloudKitError.authError
        }
        
        do {
            let recordID = CKRecord.ID(recordName: "UserPreferences")
            let record = try await privateDatabase.record(for: recordID)
            
            print("CloudKit: Found remote preferences record")
            
            // Convert CKRecord back to UserPreferences
            let preferences = UserPreferences()
            
            if let videoQuality = record["defaultVideoQuality"] as? String,
               let quality = VideoQuality(rawValue: videoQuality) {
                preferences.defaultVideoQuality = quality
            }
            
            if let theme = record["preferredTheme"] as? String,
               let appTheme = AppTheme(rawValue: theme) {
                preferences.preferredTheme = appTheme
            }
            
            preferences.autoUploadToCloud = record["autoUploadToCloud"] as? Bool ?? preferences.autoUploadToCloud
            preferences.saveToPhotosLibrary = record["saveToPhotosLibrary"] as? Bool ?? preferences.saveToPhotosLibrary
            preferences.enableHapticFeedback = record["enableHapticFeedback"] as? Bool ?? preferences.enableHapticFeedback
            preferences.showOnboardingTips = record["showOnboardingTips"] as? Bool ?? preferences.showOnboardingTips
            preferences.enableDebugMode = record["enableDebugMode"] as? Bool ?? preferences.enableDebugMode
            preferences.syncHighlightsOnly = record["syncHighlightsOnly"] as? Bool ?? preferences.syncHighlightsOnly
            preferences.maxVideoFileSize = record["maxVideoFileSize"] as? Int ?? preferences.maxVideoFileSize
            preferences.autoDeleteAfterUpload = record["autoDeleteAfterUpload"] as? Bool ?? preferences.autoDeleteAfterUpload
            preferences.enableAnalytics = record["enableAnalytics"] as? Bool ?? preferences.enableAnalytics
            preferences.shareUsageData = record["shareUsageData"] as? Bool ?? preferences.shareUsageData
            preferences.enableUploadNotifications = record["enableUploadNotifications"] as? Bool ?? preferences.enableUploadNotifications
            preferences.enableGameReminders = record["enableGameReminders"] as? Bool ?? preferences.enableGameReminders
            
            // Set lastModified from CloudKit record
            if let lastModified = record["lastModified"] as? Date {
                preferences.lastModified = lastModified
            }
            
            return preferences
            
        } catch {
            // If record doesn't exist, return nil (not an error)
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("CloudKit: No remote preferences found (first time setup)")
                return nil
            }
            
            print("CloudKit: Error fetching preferences: \(error)")
            let categorizedError = categorizeError(error)
            
            // Don't throw recordNotFound errors - they're expected for first-time users
            if case .recordNotFound = categorizedError {
                return nil
            }
            
            throw categorizedError
        }
    }
    
    func syncUserPreferences(_ preferences: UserPreferences) async throws {
        guard isCloudKitAvailable && isSignedInToiCloud else {
            throw CloudKitError.authError
        }
        
        syncStatus = .syncing
        cloudKitStatus = .syncing
        
        do {
            // Use a consistent record ID for user preferences
            let recordID = CKRecord.ID(recordName: "UserPreferences")
            
            // Try to fetch existing record first for conflict resolution
            let record: CKRecord
            do {
                let existingRecord = try await retryCloudKitOperation {
                    try await privateDatabase.record(for: recordID)
                }
                
                // Check for conflicts using timestamps
                if let remoteModified = existingRecord["lastModified"] as? Date {
                    let localModified = preferences.lastModified
                    
                    if remoteModified > localModified {
                        print("CloudKit: Remote data is newer, potential conflict detected")
                        // You could implement merge logic here or throw a specific conflict error
                        // For now, we'll proceed with local changes (last-write-wins)
                    }
                }
                
                record = existingRecord
                print("CloudKit: Found existing preferences record")
            } catch {
                // Record doesn't exist, create new one
                record = CKRecord(recordType: "UserPreferences", recordID: recordID)
                print("CloudKit: Creating new preferences record")
            }
            
            // Update record with current preferences
            record["defaultVideoQuality"] = preferences.defaultVideoQuality.rawValue
            record["autoUploadToCloud"] = preferences.autoUploadToCloud
            record["saveToPhotosLibrary"] = preferences.saveToPhotosLibrary
            record["enableHapticFeedback"] = preferences.enableHapticFeedback
            record["preferredTheme"] = preferences.preferredTheme.rawValue
            record["showOnboardingTips"] = preferences.showOnboardingTips
            record["enableDebugMode"] = preferences.enableDebugMode
            record["syncHighlightsOnly"] = preferences.syncHighlightsOnly
            record["maxVideoFileSize"] = preferences.maxVideoFileSize
            record["autoDeleteAfterUpload"] = preferences.autoDeleteAfterUpload
            record["enableAnalytics"] = preferences.enableAnalytics
            record["shareUsageData"] = preferences.shareUsageData
            record["enableUploadNotifications"] = preferences.enableUploadNotifications
            record["enableGameReminders"] = preferences.enableGameReminders
            record["lastModified"] = Date()
            
            // Save to CloudKit with retry logic
            _ = try await retryCloudKitOperation {
                try await privateDatabase.save(record)
            }
            
            print("CloudKit: Preferences successfully synced to iCloud")
            
            await MainActor.run {
                syncStatus = .success
                cloudKitStatus = .available
            }
            
        } catch {
            let cloudKitError = categorizeError(error)
            print("CloudKit: Sync failed with error: \(error)")
            
            await MainActor.run {
                syncStatus = .failed(cloudKitError)
                self.cloudKitStatus = .syncFailed(error: cloudKitError)
            }
            
            throw cloudKitError
        }
    }
    
    // MARK: - Container Registration
}

