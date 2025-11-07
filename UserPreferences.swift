//
//  UserPreferences.swift
//  PlayerPath
//
//  User preferences model with CloudKit sync
//

import SwiftUI
import SwiftData
import CloudKit

@Model
class UserPreferences {
    var id: UUID = UUID()
    
    // Video Recording Preferences
    var defaultVideoQuality: VideoQuality = .high
    var autoUploadToCloud: Bool = true
    var saveToPhotosLibrary: Bool = false
    var enableHapticFeedback: Bool = true
    
    // UI Preferences
    var preferredTheme: AppTheme = .system
    var showOnboardingTips: Bool = true
    var enableDebugMode: Bool = false
    
    // Cloud Sync Preferences
    var syncHighlightsOnly: Bool = false
    var maxVideoFileSize: Int = 500 // MB
    var autoDeleteAfterUpload: Bool = false
    
    // Analytics Preferences
    var enableAnalytics: Bool = true
    var shareUsageData: Bool = false
    
    // Notification Preferences
    var enableUploadNotifications: Bool = true
    var enableGameReminders: Bool = true
    
    init() {
        // Initialize with default values
    }
    
    // Convenience method to get shared preferences
    static func shared(from context: ModelContext) -> UserPreferences {
        let descriptor = FetchDescriptor<UserPreferences>()
        do {
            let preferences = try context.fetch(descriptor)
            return preferences.first ?? UserPreferences()
        } catch {
            print("Error fetching user preferences: \(error)")
            return UserPreferences()
        }
    }
}

enum VideoQuality: String, CaseIterable, Codable {
    case low = "Low (720p)"
    case medium = "Medium (1080p)"
    case high = "High (4K)"
    
    var resolution: String {
        switch self {
        case .low: return "720p"
        case .medium: return "1080p"
        case .high: return "4K"
        }
    }
}

enum AppTheme: String, CaseIterable, Codable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"
}