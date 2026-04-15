//
//  UserPreferences.swift
//  PlayerPath
//
//  User preferences model
//

import SwiftUI
import SwiftData
import os

private let prefsLog = Logger(subsystem: "com.playerpath.app", category: "UserPreferences")

// MARK: - Model
@Model
final class UserPreferences {
    // Immutable identity for stability
    private(set) var id: UUID = UUID()

    // MARK: - Video Recording Preferences
    var autoUploadMode: AutoUploadMode? { didSet { markAsModified() } }
    var saveToPhotosLibrary: Bool = false { didSet { markAsModified() } }
    var enableHapticFeedback: Bool = true { didSet { markAsModified() } }

    // Legacy property for backwards compatibility - computed from autoUploadMode
    var autoUploadToCloud: Bool {
        get { autoUploadMode != .off }
        set { autoUploadMode = newValue ? .wifiOnly : .off }
    }

    // Legacy property for backwards compatibility - computed from autoUploadMode.
    // Precondition: the setter is a no-op when autoUploadMode == .off. Callers
    // must enable uploads (autoUploadMode = .wifiOnly or .always) first. The UI
    // gates this toggle behind the auto-upload switch.
    var allowCellularUploads: Bool {
        get { autoUploadMode == .always }
        set { if newValue && autoUploadMode != .off { autoUploadMode = .always } }
    }

    // MARK: - UI Preferences
    var preferredTheme: AppTheme? { didSet { markAsModified() } }
    var showOnboardingTips: Bool = true { didSet { markAsModified() } }

    // MARK: - Cloud Sync Preferences
    var syncHighlightsOnly: Bool = false { didSet { markAsModified() } }
    // MB. Range 50–2000 (2 GB), enforced by the slider in UserPreferencesView.
    // No programmatic setter exists; add one here if a migration/sync path
    // ever writes this directly.
    var maxVideoFileSize: Int = 500 { didSet { markAsModified() } }
    var autoDeleteAfterUpload: Bool = false { didSet { markAsModified() } }

    // MARK: - Analytics Preferences
    var enableAnalytics: Bool = true { didSet { markAsModified() } }

    // MARK: - Notification Preferences
    var enableUploadNotifications: Bool = true { didSet { markAsModified() } }
    var enableGameReminders: Bool = true { didSet { markAsModified() } }
    var gameReminderMinutes: Int = 30 { didSet { markAsModified() } }

    // MARK: - Sync metadata
    var lastModified: Date = Date()

    // MARK: - Init
    init() {
        self.autoUploadMode = .wifiOnly
        self.preferredTheme = .system
        self.lastModified = Date()
    }

    // MARK: - Mutation helpers
    func markAsModified() {
        self.lastModified = Date()
    }

    // Convenience method to get shared preferences (fetch-or-create persisted singleton)
    static func shared(in context: ModelContext) -> UserPreferences {
        // Fetch all and enforce single-instance semantics by keeping the newest
        let descriptor = FetchDescriptor<UserPreferences>()
        if let all = try? context.fetch(descriptor), let first = all.first {
            if all.count > 1 {
                // Keep the most recently modified, delete the rest
                let sorted = all.sorted { $0.lastModified > $1.lastModified }
                guard let keep = sorted.first else { return first }
                for extra in sorted.dropFirst() {
                    context.delete(extra)
                }
                do { try context.save() } catch { prefsLog.error("Failed to save after deduplicating preferences: \(error.localizedDescription)") }
                return keep
            }
            return first
        }
        let prefs = UserPreferences()
        context.insert(prefs)
        return prefs
    }
}

/// Auto-upload mode for videos after recording
enum AutoUploadMode: String, CaseIterable, Codable {
    case off = "off"
    case wifiOnly = "wifi_only"
    case always = "always"

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .wifiOnly: return "Wi-Fi Only"
        case .always: return "Always"
        }
    }

    var description: String {
        switch self {
        case .off: return "Upload videos manually"
        case .wifiOnly: return "Auto-upload on Wi-Fi (recommended)"
        case .always: return "Auto-upload on Wi-Fi & Cellular"
        }
    }

    var icon: String {
        switch self {
        case .off: return "icloud.slash"
        case .wifiOnly: return "wifi"
        case .always: return "icloud.and.arrow.up"
        }
    }
}

/// App theme preference; raw values are stable storage keys, not UI strings.
enum AppTheme: String, CaseIterable, Codable {
    case light = "light"
    case dark = "dark"
    case system = "system"

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}
