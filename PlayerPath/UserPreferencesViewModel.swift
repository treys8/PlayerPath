import SwiftUI
import SwiftData
import Combine
import os

@MainActor
final class UserPreferencesViewModel: ObservableObject {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.playerpath", category: "UserPreferences")

    var modelContext: ModelContext?
    func attach(modelContext: ModelContext?) {
        self.modelContext = modelContext
    }

    @Published var preferences: UserPreferences?
    @Published var hasUnsavedChanges = false

    func load() async {
        guard let context = modelContext else { return }

        let fetchDescriptor = FetchDescriptor<UserPreferences>(
            sortBy: [SortDescriptor(\UserPreferences.lastModified, order: .reverse)]
        )
        do {
            let results = try context.fetch(fetchDescriptor)
            if let newest = results.first {
                // Clean up duplicates — keep the most recently modified
                if results.count > 1 {
                    for extra in results.dropFirst() {
                        context.delete(extra)
                    }
                    ErrorHandlerService.shared.saveContext(context, caller: "UserPreferencesVM.deduplicatePreferences")
                }
                preferences = newest
            } else {
                let newPreferences = UserPreferences()
                context.insert(newPreferences)
                try context.save()
                preferences = newPreferences
            }
        } catch {
            Self.logger.error("Failed to load preferences: \(error.localizedDescription)")
        }
    }

    func save() async throws {
        guard let context = modelContext, let _ = preferences else { return }
        try context.save()
        hasUnsavedChanges = false
    }

    func update<T>(_ keyPath: WritableKeyPath<UserPreferences, T>, to newValue: T) {
        preferences?[keyPath: keyPath] = newValue
        hasUnsavedChanges = true
        objectWillChange.send()
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
