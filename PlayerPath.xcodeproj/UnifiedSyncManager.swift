//
//  UnifiedSyncManager.swift
//  PlayerPath
//
//  Created by Assistant on 10/30/25.
//

import Foundation
import CloudKit
import SwiftUI
import OSLog
import Combine

// MARK: - Syncable Protocol
protocol Syncable {
    var id: String { get }
    var lastModified: Date { get set }
    var recordType: String { get }
    
    func toCKRecord() -> CKRecord
    init(from record: CKRecord) throws
}

// MARK: - Sync Status and Conflict Resolution
@MainActor
@Observable
final class UnifiedSyncManager {
    static let shared = UnifiedSyncManager()
    
    private let logger = Logger(subsystem: "PlayerPath", category: "UnifiedSyncManager")
    private let container = CKContainer.default()
    private var privateDatabase: CKDatabase { container.privateCloudDatabase }
    
    // MARK: - Published Properties
    var syncStatus: SyncStatus = .idle
    var lastSyncDate: Date?
    var isInitialSyncCompleted = false
    var pendingOperations: [String: SyncOperation] = [:]
    
    // MARK: - Sync Configuration
    private let maxBatchSize = 20
    private let syncInterval: TimeInterval = 300 // 5 minutes
    private var syncTimer: Timer?
    
    enum SyncStatus {
        case idle
        case syncing(entity: String, progress: Double)
        case success(lastSynced: Date)
        case failed(error: CloudKitError)
        case conflictResolution(conflicts: [SyncConflict])
    }
    
    enum SyncOperation {
        case create(Syncable)
        case update(Syncable)
        case delete(String, recordType: String)
        
        var id: String {
            switch self {
            case .create(let item), .update(let item):
                return item.id
            case .delete(let id, _):
                return id
            }
        }
    }
    
    struct SyncConflict {
        let id: String
        let recordType: String
        let localItem: Syncable?
        let remoteRecord: CKRecord
        let conflictType: ConflictType
        
        enum ConflictType {
            case updateUpdate // Both local and remote were modified
            case deleteUpdate // Local deleted, remote updated
            case updateDelete // Local updated, remote deleted
        }
    }
    
    enum CloudKitError: LocalizedError {
        case networkError
        case authenticationFailed
        case quotaExceeded
        case rateLimited(retryAfter: TimeInterval)
        case recordConflict(SyncConflict)
        case partialFailure([String: Error])
        case unknownError(Error)
        
        var errorDescription: String? {
            switch self {
            case .networkError:
                return "Network connection failed"
            case .authenticationFailed:
                return "iCloud authentication required"
            case .quotaExceeded:
                return "iCloud storage quota exceeded"
            case .rateLimited(let retryAfter):
                return "Rate limited, retry in \(Int(retryAfter)) seconds"
            case .recordConflict:
                return "Data conflict detected"
            case .partialFailure:
                return "Some items failed to sync"
            case .unknownError(let error):
                return error.localizedDescription
            }
        }
    }
    
    private init() {
        setupPeriodicSync()
    }
    
    // MARK: - Core Sync Operations
    
    /// Perform complete sync for all registered entity types
    func performFullSync() async {
        logger.info("Starting full sync operation")
        
        syncStatus = .syncing(entity: "All", progress: 0.0)
        
        do {
            // Sync user preferences
            try await syncEntity(type: UserPreferences.self, entity: "UserPreferences")
            
            // TODO: Add other entities as they're implemented
            // try await syncEntity(type: VideoRecord.self, entity: "VideoRecord")
            // try await syncEntity(type: GameSession.self, entity: "GameSession")
            
            lastSyncDate = Date()
            isInitialSyncCompleted = true
            syncStatus = .success(lastSynced: lastSyncDate!)
            
            logger.info("Full sync completed successfully")
            
        } catch {
            let cloudKitError = categorizeError(error)
            syncStatus = .failed(error: cloudKitError)
            logger.error("Full sync failed: \(error)")
        }
    }
    
    /// Sync a specific entity type
    private func syncEntity<T: Syncable>(type: T.Type, entity: String) async throws {
        logger.info("Syncing \(entity)")
        syncStatus = .syncing(entity: entity, progress: 0.0)
        
        // Fetch remote changes
        let remoteRecords = try await fetchRemoteRecords(recordType: T.init().recordType)
        
        // TODO: Implement local data source integration
        // For now, we'll work with UserPreferences as an example
        if entity == "UserPreferences" {
            try await syncUserPreferences(remoteRecords: remoteRecords)
        }
    }
    
    /// Fetch all remote records for a given type
    private func fetchRemoteRecords(recordType: String) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
        
        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        
        repeat {
            let (records, nextCursor) = try await performQuery(query: query, cursor: cursor)
            allRecords.append(contentsOf: records)
            cursor = nextCursor
        } while cursor != nil
        
        return allRecords
    }
    
    private func performQuery(query: CKQuery, cursor: CKQueryOperation.Cursor?) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        if let cursor = cursor {
            let (matchResults, queryCursor) = try await privateDatabase.records(continuingMatchFrom: cursor)
            let records = try matchResults.compactMap { _, result in
                try result.get()
            }
            return (records, queryCursor)
        } else {
            let (matchResults, queryCursor) = try await privateDatabase.records(matching: query)
            let records = try matchResults.compactMap { _, result in
                try result.get()
            }
            return (records, queryCursor)
        }
    }
    
    // MARK: - Conflict Resolution
    
    /// Queue an operation for later sync
    func queueOperation(_ operation: SyncOperation) {
        pendingOperations[operation.id] = operation
        logger.info("Queued \(operation) for sync")
        
        // Trigger sync if we have many pending operations
        if pendingOperations.count >= maxBatchSize {
            Task {
                await performFullSync()
            }
        }
    }
    
    /// Resolve sync conflicts
    func resolveConflict(_ conflict: SyncConflict, resolution: ConflictResolution) async throws {
        logger.info("Resolving conflict for \(conflict.id)")
        
        switch resolution {
        case .useLocal:
            if let localItem = conflict.localItem {
                let record = localItem.toCKRecord()
                try await privateDatabase.save(record)
            }
        case .useRemote:
            // TODO: Update local storage with remote data
            break
        case .merge(let mergedItem):
            let record = mergedItem.toCKRecord()
            try await privateDatabase.save(record)
        }
    }
    
    enum ConflictResolution {
        case useLocal
        case useRemote
        case merge(Syncable)
    }
    
    // MARK: - User Preferences Specific Sync
    
    private func syncUserPreferences(remoteRecords: [CKRecord]) async throws {
        // This integrates with your existing CloudKitManager
        let cloudKitManager = CloudKitManager.shared
        
        // Check if we have any remote preferences
        if let remoteRecord = remoteRecords.first {
            // TODO: Get local preferences from your app's data store
            // For now, create a dummy local preferences for comparison
            let localPreferences = UserPreferences()
            
            // Check for conflicts
            if let remoteModified = remoteRecord.modificationDate,
               remoteModified > localPreferences.lastModified {
                
                // Remote is newer, but check if local has unsaved changes
                if pendingOperations.keys.contains("UserPreferences") {
                    // We have a conflict!
                    let conflict = SyncConflict(
                        id: "UserPreferences",
                        recordType: "UserPreferences",
                        localItem: localPreferences,
                        remoteRecord: remoteRecord,
                        conflictType: .updateUpdate
                    )
                    
                    syncStatus = .conflictResolution(conflicts: [conflict])
                    return
                }
            }
            
            // No conflict, proceed with normal sync
            _ = try await cloudKitManager.fetchUserPreferences()
        }
        
        // Upload any pending local changes
        if let pendingOp = pendingOperations["UserPreferences"] {
            switch pendingOp {
            case .create(let preferences), .update(let preferences):
                if let userPrefs = preferences as? UserPreferences {
                    try await cloudKitManager.syncUserPreferences(userPrefs)
                }
            case .delete:
                // Handle deletion if needed
                break
            }
            
            pendingOperations.removeValue(forKey: "UserPreferences")
        }
    }
    
    // MARK: - Periodic Sync
    
    private func setupPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { _ in
            Task { @MainActor in
                await self.performFullSync()
            }
        }
    }
    
    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    // MARK: - Error Categorization
    
    private func categorizeError(_ error: Error) -> CloudKitError {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                return .networkError
            case .notAuthenticated:
                return .authenticationFailed
            case .quotaExceeded:
                return .quotaExceeded
            case .requestRateLimited:
                let retryAfter = ckError.retryAfterSeconds ?? 60
                return .rateLimited(retryAfter: retryAfter)
            case .partialFailure:
                var errors: [String: Error] = [:]
                if let partialErrors = ckError.partialErrorsByItemID {
                    for (key, error) in partialErrors {
                        if let recordID = key as? CKRecord.ID {
                            errors[recordID.recordName] = error
                        }
                    }
                }
                return .partialFailure(errors)
            default:
                return .unknownError(error)
            }
        }
        
        return .unknownError(error)
    }
}

// MARK: - UserPreferences Syncable Implementation

extension UserPreferences: Syncable {
    var recordType: String { "UserPreferences" }
    
    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        
        record["defaultVideoQuality"] = defaultVideoQuality.rawValue
        record["autoUploadToCloud"] = autoUploadToCloud
        record["saveToPhotosLibrary"] = saveToPhotosLibrary
        record["enableHapticFeedback"] = enableHapticFeedback
        record["preferredTheme"] = preferredTheme.rawValue
        record["showOnboardingTips"] = showOnboardingTips
        record["enableDebugMode"] = enableDebugMode
        record["syncHighlightsOnly"] = syncHighlightsOnly
        record["maxVideoFileSize"] = maxVideoFileSize
        record["autoDeleteAfterUpload"] = autoDeleteAfterUpload
        record["enableAnalytics"] = enableAnalytics
        record["shareUsageData"] = shareUsageData
        record["enableUploadNotifications"] = enableUploadNotifications
        record["enableGameReminders"] = enableGameReminders
        record["lastModified"] = lastModified
        
        return record
    }
    
    convenience init(from record: CKRecord) throws {
        self.init()
        
        if let videoQuality = record["defaultVideoQuality"] as? String,
           let quality = VideoQuality(rawValue: videoQuality) {
            self.defaultVideoQuality = quality
        }
        
        if let theme = record["preferredTheme"] as? String,
           let appTheme = AppTheme(rawValue: theme) {
            self.preferredTheme = appTheme
        }
        
        self.autoUploadToCloud = record["autoUploadToCloud"] as? Bool ?? autoUploadToCloud
        self.saveToPhotosLibrary = record["saveToPhotosLibrary"] as? Bool ?? saveToPhotosLibrary
        self.enableHapticFeedback = record["enableHapticFeedback"] as? Bool ?? enableHapticFeedback
        self.showOnboardingTips = record["showOnboardingTips"] as? Bool ?? showOnboardingTips
        self.enableDebugMode = record["enableDebugMode"] as? Bool ?? enableDebugMode
        self.syncHighlightsOnly = record["syncHighlightsOnly"] as? Bool ?? syncHighlightsOnly
        self.maxVideoFileSize = record["maxVideoFileSize"] as? Int ?? maxVideoFileSize
        self.autoDeleteAfterUpload = record["autoDeleteAfterUpload"] as? Bool ?? autoDeleteAfterUpload
        self.enableAnalytics = record["enableAnalytics"] as? Bool ?? enableAnalytics
        self.shareUsageData = record["shareUsageData"] as? Bool ?? shareUsageData
        self.enableUploadNotifications = record["enableUploadNotifications"] as? Bool ?? enableUploadNotifications
        self.enableGameReminders = record["enableGameReminders"] as? Bool ?? enableGameReminders
        
        if let lastModified = record["lastModified"] as? Date {
            self.lastModified = lastModified
        }
    }
}

// MARK: - Sync Status View

struct SyncStatusView: View {
    @State private var syncManager = UnifiedSyncManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: syncStatusIcon)
                    .foregroundColor(syncStatusColor)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync Status")
                        .font(.headline)
                    
                    Text(syncStatusDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if case .syncing = syncManager.syncStatus {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if case .syncing(let entity, let progress) = syncManager.syncStatus {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Syncing \(entity)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
            }
            
            if case .conflictResolution(let conflicts) = syncManager.syncStatus {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync Conflicts")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    
                    ForEach(conflicts, id: \.id) { conflict in
                        ConflictResolutionView(conflict: conflict) { resolution in
                            Task {
                                try await syncManager.resolveConflict(conflict, resolution: resolution)
                            }
                        }
                    }
                }
            }
            
            HStack {
                if let lastSync = syncManager.lastSyncDate {
                    Text("Last sync: \(lastSync, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Sync Now") {
                    Task {
                        await syncManager.performFullSync()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(syncManager.syncStatus.isSyncing)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var syncStatusIcon: String {
        switch syncManager.syncStatus {
        case .idle:
            return "icloud"
        case .syncing:
            return "icloud.and.arrow.up"
        case .success:
            return "icloud.and.arrow.up.fill"
        case .failed:
            return "icloud.slash"
        case .conflictResolution:
            return "exclamationmark.icloud"
        }
    }
    
    private var syncStatusColor: Color {
        switch syncManager.syncStatus {
        case .idle:
            return .gray
        case .syncing:
            return .blue
        case .success:
            return .green
        case .failed:
            return .red
        case .conflictResolution:
            return .orange
        }
    }
    
    private var syncStatusDescription: String {
        switch syncManager.syncStatus {
        case .idle:
            return "Ready to sync"
        case .syncing(let entity, _):
            return "Syncing \(entity)..."
        case .success:
            return "All data is up to date"
        case .failed(let error):
            return "Sync failed: \(error.localizedDescription)"
        case .conflictResolution:
            return "Conflicts need resolution"
        }
    }
}

extension UnifiedSyncManager.SyncStatus {
    var isSyncing: Bool {
        if case .syncing = self {
            return true
        }
        return false
    }
}

// MARK: - Conflict Resolution View

struct ConflictResolutionView: View {
    let conflict: UnifiedSyncManager.SyncConflict
    let onResolve: (UnifiedSyncManager.ConflictResolution) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(conflict.recordType)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("Choose which version to keep:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button("Use Local") {
                    onResolve(.useLocal)
                }
                .buttonStyle(.bordered)
                
                Button("Use Remote") {
                    onResolve(.useRemote)
                }
                .buttonStyle(.bordered)
                
                // TODO: Implement merge UI for complex conflicts
            }
        }
        .padding(.vertical, 4)
    }
}