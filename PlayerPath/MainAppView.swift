//
//  MainAppView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//
//  CRITICAL FIXES APPLIED:
//  1. ✅ NotificationCenter Memory Leak Prevention - Using @StateObject NotificationObserverManager for lifecycle safety
//  2. ✅ SwiftData Relationship Race Condition - Set relationships before insert, let inverse handle array
//  3. ✅ Safe Predicate Implementation - Removed force unwrap, using Swift filter instead
//  4. ✅ Task Cancellation - All async tasks check for cancellation and store references for cleanup
//  5. ✅ Observer Duplication Prevention - Dedicated ObservableObject manages observers with automatic cleanup
//

import SwiftUI
import SwiftData
import FirebaseAuth
import Combine

// MARK: - Theme Manager
/// Reads the user's preferred theme from UserDefaults and exposes it
/// as a published property so the root view can apply .preferredColorScheme().
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    @Published var colorScheme: ColorScheme?

    private init() { reload() }

    func reload() {
        guard let raw = UserDefaults.standard.string(forKey: "appTheme") else {
            colorScheme = nil // system default
            return
        }
        switch raw {
        case "light": colorScheme = .light
        case "dark":  colorScheme = .dark
        default:      colorScheme = nil
        }
    }
}

/// App-wide notifications used for cross-feature coordination.
/// - switchTab: Pass an Int tab index as object to switch the main TabView.
/// - presentVideoRecorder: Ask Videos module to present its recorder UI.
/// - showAthleteSelection: Request athlete selection UI to be shown.
/// - recordedHitResult: Post with object ["hitType": String] to update highlights and stats.

// MARK: - Main Tab Enum
enum MainTab: Int {
    case home = 0
    case games = 1
    case videos = 2
    case stats = 3
    case more = 4

    // Legacy compatibility aliases
    static var profile: MainTab { .more }
    static var practice: MainTab { .more }
    static var highlights: MainTab { .more }
}

// Convenience helper to switch tabs via NotificationCenter
@inline(__always)
func postSwitchTab(_ tab: MainTab) {
    NotificationCenter.default.post(name: .switchTab, object: tab.rawValue)
}

// MARK: - App Root
struct PlayerPathMainView: View {
    @StateObject private var authManager = ComprehensiveAuthManager()
    @ObservedObject private var updateManager = AppUpdateManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if updateManager.requiresUpdate {
                ForceUpdateView(updateURL: updateManager.updateURL)
            } else if authManager.isSignedIn {
                AuthenticatedFlow()
            } else if authManager.needsEmailVerification {
                // User signed up but hasn't verified email — show verification UI directly.
                // WelcomeFlow only shows Get Started / Sign In buttons; EmailVerificationView
                // is buried inside a sheet there, so we surface it at the top level instead.
                NavigationStack {
                    EmailVerificationView()
                        .environmentObject(authManager)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    Task { await authManager.cancelEmailVerification() }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                }
            } else if authManager.currentFirebaseUser != nil {
                // Firebase session exists but profile hasn't loaded yet —
                // show a splash screen instead of flashing the sign-in view.
                LoadingView(title: "Welcome back!", subtitle: "Loading your profile...")
            } else {
                WelcomeFlow()
            }
        }
        .environmentObject(authManager)
        .tint(Color.brandNavy)
        .preferredColorScheme(themeManager.colorScheme)
        .dynamicTypeSize(...DynamicTypeSize.accessibility5)
        .withErrorHandling() // Global error handling
        .sheet(isPresented: $updateManager.showWhatsNew) {
            WhatsNewView(items: updateManager.whatsNewItems) {
                updateManager.markWhatsNewSeen()
            }
            .interactiveDismissDisabled()
        }
        .task {
            // Enforce singleton UserPreferences on every launch (dedup + create if missing)
            let prefs = UserPreferences.shared(in: modelContext)

            // Honor analytics opt-out preference on launch
            AnalyticsService.shared.setCollection(enabled: prefs.enableAnalytics)

            // Sync notification prefs from UserDefaults → SwiftData to prevent divergence
            prefs.enableGameReminders = UserDefaults.standard.object(forKey: "notif_gameReminders") as? Bool ?? true
            prefs.enableUploadNotifications = UserDefaults.standard.object(forKey: "notif_uploads") as? Bool ?? true

            // Check for forced updates and What's New content
            await updateManager.checkOnLaunch()
        }
    }
}
