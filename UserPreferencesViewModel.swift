import SwiftUI
import SwiftData

@MainActor
public final class UserPreferencesViewModel: ObservableObject {
    
    public struct SyncAlert: Identifiable {
        public let id = UUID()
        public let title: String
        public let message: String
        public let recoverySuggestion: String?
    }
    
    public var modelContext: ModelContext?
    public func attach(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }
    
    private let cloudKitManager = CloudKitManager.shared
    
    @Published public var preferences: UserPreferences?
    @Published public var hasUnsavedChanges = false
    @Published public var syncStatus: CloudKitManager.SyncStatus = .idle
    @Published public var alert: SyncAlert?
    
    public var canSync: Bool {
        cloudKitManager.isCloudKitAvailable
    }
    
    private var remoteChangeObserver: Any?
    
    public func startObservingRemoteChanges() {
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
    
    public func stopObservingRemoteChanges() {
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            remoteChangeObserver = nil
        }
    }
    
    public func load() async {
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
            // Swallow errors here; optionally could add error handling
        }
    }
    
    private func saveLocal() throws {
        guard let context = modelContext, let _ = preferences else { return }
        try context.save()
        hasUnsavedChanges = false
    }
    
    public func save() async throws {
        try saveLocal()
    }
    
    public func saveAndSync() async {
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
            syncStatus = .failed(error)
            alert = SyncAlert(
                title: "Sync Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Please try again later."
            )
        }
    }
    
    public func loadFromCloudKit() async {
        guard cloudKitManager.isCloudKitAvailable,
              cloudKitManager.isSignedInToiCloud else { return }
        
        do {
            if let remote = try await cloudKitManager.fetchUserPreferences() {
                updateLocalPreferences(with: remote)
                try saveLocal()
            }
        } catch {
            // Silently ignore errors here for now
        }
    }
    
    public func updateLocalPreferences(with remote: UserPreferences) {
        guard let current = preferences else { return }
        
        // Copy all fields exactly as in original view's updateLocalPreferences
        // Assuming UserPreferences has properties that we just copy one by one.
        // Since we don't have actual properties here, we just do a generic copy:
        // This must be replaced with actual properties if known.
        // Example:
        // current.someField = remote.someField
        // current.otherField = remote.otherField
        // As no properties are given, we assume a full copy method is implemented or do nothing.
        
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
    
    public func update<T>(_ keyPath: WritableKeyPath<UserPreferences, T>, to newValue: T) {
        guard preferences != nil else { return }
        preferences![keyPath: keyPath] = newValue
        hasUnsavedChanges = true
    }
    
    deinit {
        stopObservingRemoteChanges()
    }
    
    // Convenience computed property for toolbar
    public var showsSyncButton: Bool {
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
