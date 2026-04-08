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
    var defaultVideoQuality: VideoQuality? { didSet { markAsModified() } }
    var autoUploadMode: AutoUploadMode? { didSet { markAsModified() } }
    var saveToPhotosLibrary: Bool = false { didSet { markAsModified() } }
    var enableHapticFeedback: Bool = true { didSet { markAsModified() } }

    // Legacy property for backwards compatibility - computed from autoUploadMode
    var autoUploadToCloud: Bool {
        get { autoUploadMode != .off }
        set { autoUploadMode = newValue ? .wifiOnly : .off }
    }

    // Legacy property for backwards compatibility - computed from autoUploadMode
    var allowCellularUploads: Bool {
        get { autoUploadMode == .always }
        set { if newValue && autoUploadMode != .off { autoUploadMode = .always } }
    }

    // MARK: - UI Preferences
    var preferredTheme: AppTheme? { didSet { markAsModified() } }
    var showOnboardingTips: Bool = true { didSet { markAsModified() } }

    // MARK: - Cloud Sync Preferences
    var syncHighlightsOnly: Bool = false { didSet { markAsModified() } }
    // Clamped in MB to a reasonable range (50MB–10GB).
    // Clamping is done in the UI layer / setter to avoid didSet re-entrancy.
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
        self.defaultVideoQuality = .high
        self.autoUploadMode = .wifiOnly
        self.preferredTheme = .system
        self.lastModified = Date()
    }

    // MARK: - Mutation helpers
    func markAsModified() {
        self.lastModified = Date()
    }

    /// Resolve a sync conflict by keeping the most recently modified instance
    /// and deleting the loser from the given context.
    static func resolveConflict(local: UserPreferences, remote: UserPreferences, in context: ModelContext) -> UserPreferences {
        let (keep, discard) = (local.lastModified >= remote.lastModified)
            ? (local, remote) : (remote, local)
        context.delete(discard)
        return keep
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

/// Represents capture/export quality; raw values are stable storage keys, not UI strings.
enum VideoQuality: String, CaseIterable, Codable {
    // Stable storage values independent of UI strings
    case low = "low"
    case medium = "medium"
    case high = "high"

    // UI-facing text
    var displayName: String {
        switch self {
        case .low: return "Low (720p)"
        case .medium: return "Medium (1080p)"
        case .high: return "High (4K)"
        }
    }

    var resolution: String {
        switch self {
        case .low: return "720p"
        case .medium: return "1080p"
        case .high: return "4K"
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
