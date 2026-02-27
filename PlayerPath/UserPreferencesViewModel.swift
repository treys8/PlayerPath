import SwiftUI
import SwiftData
import Combine
import os

@MainActor
final class UserPreferencesViewModel: ObservableObject {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.playerpath", category: "UserPreferences")

    struct SyncAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let recoverySuggestion: String?
    }
    
    var modelContext: ModelContext?
    func attach(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }
    
    private let cloudKitManager = CloudKitManager.shared
    
    @Published var preferences: UserPreferences?
    @Published var hasUnsavedChanges = false
    @Published var syncStatus: CloudKitManager.SyncStatus = .idle
    @Published var alert: SyncAlert?
    
    var canSync: Bool {
        cloudKitManager.isCloudKitAvailable
    }
    
    private var remoteChangeObserver: Any?
    
    func startObservingRemoteChanges() {
        stopObservingRemoteChanges()
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .userPreferencesDidChangeRemotely,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.loadFromCloudKit()
            }
        }
    }
    
    func stopObservingRemoteChanges() {
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            remoteChangeObserver = nil
        }
    }
    
    func load() async {
        guard let context = modelContext else { return }
        
        let fetchDescriptor = FetchDescriptor<UserPreferences>()
        do {
            let results = try context.fetch(fetchDescriptor)
            if let existing = results.first {
                preferences = existing
            } else {
                let newPreferences = UserPreferences()
                context.insert(newPreferences)
                try context.save()
                preferences = newPreferences
            }
            await loadFromCloudKit()
        } catch {
            Self.logger.error("Failed to load preferences: \(error.localizedDescription)")
        }
    }
    
    private func saveLocal() throws {
        guard let context = modelContext, let _ = preferences else { return }
        try context.save()
        hasUnsavedChanges = false
    }
    
    func save() async throws {
        try saveLocal()
    }
    
    func saveAndSync() async {
        guard let prefs = preferences else { return }
        
        try? saveLocal()
        
        syncStatus = .syncing
        do {
            try await cloudKitManager.syncUserPreferences(prefs)
            syncStatus = .success
            alert = SyncAlert(
                title: "Sync Success",
                message: "Preferences successfully synced to iCloud",
                recoverySuggestion: nil
            )
        } catch let error as CloudKitManager.CloudKitError {
            syncStatus = .failed(error)
            alert = SyncAlert(
                title: "Sync Failed",
                message: error.localizedDescription,
                recoverySuggestion: error.recoverySuggestion
            )
        } catch {
            let categorized = cloudKitManager.categorizeError(error)
            syncStatus = .failed(categorized)
            alert = SyncAlert(
                title: "Sync Failed",
                message: categorized.localizedDescription,
                recoverySuggestion: categorized.recoverySuggestion
            )
        }
    }
    
    func loadFromCloudKit() async {
        guard cloudKitManager.isCloudKitAvailable,
              cloudKitManager.isSignedInToiCloud else { return }
        
        do {
            if let remote = try await cloudKitManager.fetchUserPreferences() {
                updateLocalPreferences(with: remote)
                try saveLocal()
            }
        } catch {
            Self.logger.warning("Failed to load preferences from CloudKit: \(error.localizedDescription)")
        }
    }
    
    func updateLocalPreferences(with remote: UserPreferences) {
        guard let current = preferences else { return }

        // Fix U: Copy every stored property from the remote record.
        // Only apply the remote value when it is newer to avoid overwriting
        // in-flight local edits the user hasn't synced yet.
        guard remote.lastModified > current.lastModified else { return }

        current.defaultVideoQuality    = remote.defaultVideoQuality
        current.autoUploadMode         = remote.autoUploadMode
        current.saveToPhotosLibrary    = remote.saveToPhotosLibrary
        current.enableHapticFeedback   = remote.enableHapticFeedback

        current.preferredTheme         = remote.preferredTheme
        current.showOnboardingTips     = remote.showOnboardingTips

        current.syncHighlightsOnly     = remote.syncHighlightsOnly
        current.maxVideoFileSize       = remote.maxVideoFileSize
        current.autoDeleteAfterUpload  = remote.autoDeleteAfterUpload

        current.enableAnalytics        = remote.enableAnalytics
        current.shareUsageData         = remote.shareUsageData

        current.enableUploadNotifications = remote.enableUploadNotifications
        current.enableGameReminders    = remote.enableGameReminders

        // Preserve the remote timestamp so future conflict resolution is accurate
        current.lastModified = remote.lastModified
    }
    
    func update<T>(_ keyPath: WritableKeyPath<UserPreferences, T>, to newValue: T) {
        guard preferences != nil else { return }
        preferences![keyPath: keyPath] = newValue
        hasUnsavedChanges = true
    }
    
    deinit {
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            remoteChangeObserver = nil
        }
    }
    
    // Convenience computed property for toolbar
    var showsSyncButton: Bool {
        canSync
    }
}

#if DEBUG
extension UserPreferences {
    static var example: UserPreferences {
        let prefs = UserPreferences()
        // Fill with reasonable defaults here, if possible.
        // Since no properties known, leave empty.
        return prefs
    }
}
#endif

