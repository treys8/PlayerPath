//
//  CloudKitManager.swift
//  PlayerPath
//
//  Created by Assistant on 10/29/25.
//

import Foundation
import CloudKit
import SwiftUI
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
        
        isInitialized = true

    }
    
    func checkCloudKitAvailability() {
        // Assume available until checkiCloudStatusAsync proves otherwise
        isCloudKitAvailable = true
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
                
                isSignedInToiCloud = true
                cloudKitError = nil
                cloudKitStatus = .available
            } else {
                isSignedInToiCloud = false
                let reason = getStatusMessage(for: status)
                cloudKitError = reason
                cloudKitStatus = .unavailable(reason: reason)
                isCloudKitAvailable = false
            }
        } catch {
            isSignedInToiCloud = false
            isCloudKitAvailable = false

            let categorizedError = categorizeError(error)
            let errorMessage = categorizedError.localizedDescription

            cloudKitError = errorMessage
            cloudKitStatus = .unavailable(reason: errorMessage)
        }
    }
    
    // MARK: - iCloud Account Status

    func checkiCloudStatus() {
        Task {
            await checkiCloudStatusAsync()
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
        registerForRemoteNotifications()
        await createUserPreferencesSubscription()
    }
    
    @MainActor
    private func registerForRemoteNotifications() {
        #if canImport(UIKit)
        // CloudKit silent pushes (shouldSendContentAvailable) only need
        // registerForRemoteNotifications — no user-facing notification
        // permission is required.
        if !UIApplication.shared.isRegisteredForRemoteNotifications {
            UIApplication.shared.registerForRemoteNotifications()
        } else {
        }
        #else
        #endif
    }
    
    private func createUserPreferencesSubscription() async {
        guard isCloudKitAvailable && isSignedInToiCloud else {
            return
        }
        
        do {
            // Check if subscription already exists with retry logic
            let existingSubscriptions = try await retryCloudKitOperation {
                try await privateDatabase.allSubscriptions()
            }
            
            let subscriptionID = "UserPreferencesSubscription"
            
            if existingSubscriptions.contains(where: { $0.subscriptionID == subscriptionID }) {
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
            
            
        } catch {
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
            }
            
        } catch {
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
            
        } catch {
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
                await handleQueryNotification(queryNotification)
            }
        case .database:
            if let databaseNotification = notification as? CKDatabaseNotification {
                await handleDatabaseNotification(databaseNotification)
            }
        default:
            break
        }
    }
    
    private func handleQueryNotification(_ notification: CKQueryNotification) async {
        
        // Handle UserPreferences changes
        if notification.subscriptionID == "UserPreferencesSubscription" {
            NotificationCenter.default.post(name: .userPreferencesDidChangeRemotely, object: nil)
        }
    }
    
    private func handleDatabaseNotification(_ notification: CKDatabaseNotification) async {
        // Handle database-wide changes if needed
    }
    
    func registerContainer() {
        Task {
            do {

                // Try to perform a simple query to test database access
                let query = CKQuery(recordType: "TestType", predicate: NSPredicate(value: false))
                _ = try await privateDatabase.records(matching: query, resultsLimit: 1)

                cloudKitError = nil
            } catch {
                cloudKitError = "Container registration failed: \(error.localizedDescription)"
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
            let record = try await retryCloudKitOperation {
                try await privateDatabase.record(for: recordID)
            }
            
            
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
                return nil
            }
            
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
                        // You could implement merge logic here or throw a specific conflict error
                        // For now, we'll proceed with local changes (last-write-wins)
                    }
                }
                
                record = existingRecord
            } catch {
                // Record doesn't exist, create new one
                record = CKRecord(recordType: "UserPreferences", recordID: recordID)
            }
            
            // Update record with current preferences
            record["defaultVideoQuality"] = preferences.defaultVideoQuality?.rawValue ?? VideoQuality.high.rawValue
            record["autoUploadToCloud"] = preferences.autoUploadToCloud
            record["saveToPhotosLibrary"] = preferences.saveToPhotosLibrary
            record["enableHapticFeedback"] = preferences.enableHapticFeedback
            record["preferredTheme"] = preferences.preferredTheme?.rawValue ?? AppTheme.system.rawValue
            record["showOnboardingTips"] = preferences.showOnboardingTips
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
            
            
            syncStatus = .success
            cloudKitStatus = .available

        } catch {
            let cloudKitError = categorizeError(error)

            syncStatus = .failed(cloudKitError)
            cloudKitStatus = .syncFailed(error: cloudKitError)
            
            throw cloudKitError
        }
    }
    
    // MARK: - Container Registration
}

