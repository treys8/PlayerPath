//
//  MainAppView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import Combine
import os

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
}

// Convenience helper to switch tabs via NotificationCenter
func postSwitchTab(_ tab: MainTab) {
    NotificationCenter.default.post(name: .switchTab, object: tab.rawValue)
}

// MARK: - App Root
private let mainViewLog = Logger(subsystem: "com.playerpath.app", category: "MainView")

struct PlayerPathMainView: View {
    @StateObject private var authManager = ComprehensiveAuthManager()
    @ObservedObject private var updateManager = AppUpdateManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigationCoordinator) private var navigationCoordinator

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
        .onOpenURL { url in
            mainViewLog.info("OpenURL: \(url.absoluteString)")
            guard let intent = DeepLinkIntent(url: url) else { return }
            if authManager.isSignedIn {
                navigationCoordinator.handle(intent)
            } else {
                mainViewLog.info("User not signed in — deferring deep link")
                navigationCoordinator.pendingDeepLink = intent
            }
        }
        .task {
            // Enforce singleton UserPreferences on every launch (dedup + create if missing)
            let prefs = UserPreferences.shared(in: modelContext)

            // Honor analytics opt-out preference on launch
            AnalyticsService.shared.setCollection(enabled: prefs.enableAnalytics)

            // One-time migration: copy notification prefs from UserDefaults → SwiftData
            // for users upgrading from builds that used @AppStorage in
            // NotificationSettingsView. After this runs, SwiftData is the single
            // source of truth; the settings view writes only SwiftData, so re-running
            // this seed on every launch would overwrite user changes.
            let notifPrefsMigrationKey = "notif_prefs_migrated_to_swiftdata_v5"
            if !UserDefaults.standard.bool(forKey: notifPrefsMigrationKey) {
                prefs.enableGameReminders = UserDefaults.standard.object(forKey: "notif_gameReminders") as? Bool ?? true
                prefs.enableUploadNotifications = UserDefaults.standard.object(forKey: "notif_uploads") as? Bool ?? true
                prefs.gameReminderMinutes = UserDefaults.standard.object(forKey: "notif_gameReminderMinutes") as? Int ?? 30
                UserDefaults.standard.set(true, forKey: notifPrefsMigrationKey)
            }

            // One-time V20 backfill: flag pre-upgrade manual/quick-entered stats
            // so recalculateGameStatistics doesn't wipe them on the next video sync.
            ManualStatsBackfill.runIfNeeded(context: modelContext)

            // Check for forced updates and What's New content
            await updateManager.checkOnLaunch()
        }
    }
}
