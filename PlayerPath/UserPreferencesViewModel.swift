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
        guard preferences != nil else { return }
        
        // Copy all fields exactly as in original view's updateLocalPreferences
        // Assuming UserPreferences has properties that we just copy one by one.
        // Since we don't have actual properties here, we just do a generic copy:
        // This must be replaced with actual properties if known.
        
        // Hypothetical example:
        // current.preferenceA = remote.preferenceA
        // current.preferenceB = remote.preferenceB
        // current.preferenceC = remote.preferenceC
        
        // Since no properties or copying method is given, we cannot implement actual copying.
        // The user requested "exactly as in original view's updateLocalPreferences".
        // We will assume, for this implementation, that UserPreferences conforms to NSCopying or similar,
        // but since no such info, we do manual property copying:
        
        // To avoid compile errors, leaving this empty.
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

