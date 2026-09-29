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

    func load() async {
        guard let context = modelContext else { return }
        // Delegate to the canonical fetch-or-create + dedup path so this and
        // UserPreferences.shared(in:) don't race on duplicate deletion.
        preferences = UserPreferences.shared(in: context)
    }

    /// Writes and saves immediately — matches VideoRecordingSettingsView, so a
    /// preference never sits unsaved when the user backs out.
    func update<T>(_ keyPath: WritableKeyPath<UserPreferences, T>, to newValue: T) {
        preferences?[keyPath: keyPath] = newValue
        guard let context = modelContext else { return }
        ErrorHandlerService.shared.saveContext(context, caller: "UserPreferences.update")
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
