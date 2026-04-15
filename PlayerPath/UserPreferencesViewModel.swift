import SwiftUI
import SwiftData
import os

@MainActor
@Observable
final class UserPreferencesViewModel {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.playerpath", category: "UserPreferences")

    private(set) var modelContext: ModelContext?
    func attach(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }

    var preferences: UserPreferences?
    var hasUnsavedChanges = false

    func load() async {
        guard let context = modelContext else { return }
        hasUnsavedChanges = false
        // Delegate to the canonical fetch-or-create + dedup path so this and
        // UserPreferences.shared(in:) don't race on duplicate deletion.
        preferences = UserPreferences.shared(in: context)
    }

    func save() async throws {
        guard let context = modelContext, let _ = preferences else { return }
        try context.save()
        hasUnsavedChanges = false
    }

    func update<T>(_ keyPath: WritableKeyPath<UserPreferences, T>, to newValue: T) {
        preferences?[keyPath: keyPath] = newValue
        hasUnsavedChanges = true
    }
}

#if DEBUG
extension UserPreferences {
    static var example: UserPreferences {
        let prefs = UserPreferences()
        return prefs
    }
}
#endif
