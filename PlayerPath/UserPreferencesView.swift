//
//  UserPreferencesView.swift
//  PlayerPath
//
//  App Preferences: haptics, onboarding tips, golf scoring defaults, analytics.
//  Recording, upload, and on-device copy options live in
//  VideoRecordingSettingsView ("Recording & Uploads") — one home per setting.
//

import SwiftUI
import SwiftData
import TipKit

struct UserPreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Query private var allPrefs: [UserPreferences]
    @Query private var users: [User]
    @State private var showingResetTipsConfirm = false

    // Haptics.swift reads this UserDefaults key directly, so the view writes to
    // it directly too — no SwiftData mirroring.
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled: Bool = true
    @AppStorage(GolfPrefs.trackDetailedStats) private var trackDetailedGolfStats = false
    @AppStorage(GolfPrefs.preferredShotByShot) private var preferShotByShot = false

    private var isCoach: Bool { authManager.userRole == .coach }

    /// Same accessor as NotificationSettingsView: @Query for reactivity,
    /// shared(in:) as the safety net if the singleton isn't there yet.
    private var prefs: UserPreferences {
        allPrefs.first ?? UserPreferences.shared(in: modelContext)
    }

    /// Golf defaults are clutter for baseball-only and coach accounts. Any golf
    /// profile counts (a dual-sport person's golf row), matching the old gate.
    private var hasGolfAthlete: Bool {
        !isCoach && (users.first?.athletes?.contains { $0.sport == .golf } ?? false)
    }

    var body: some View {
        Form {
            generalSection
            interfaceSection
            if hasGolfAthlete {
                golfSection
            }
            privacyAnalyticsSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle("App Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset onboarding tips?",
            isPresented: $showingResetTipsConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                do {
                    try Tips.resetDatastore()
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "Tips.resetDatastore", showAlert: false)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Hints you've already dismissed will show again the next time you visit each tab.")
        }
    }

    /// Write-through: every other settings screen saves on change, so this one
    /// does too (the old Save button implied a draft that never existed —
    /// edits hit the live model immediately).
    private func prefBinding(_ keyPath: ReferenceWritableKeyPath<UserPreferences, Bool>, caller: String) -> Binding<Bool> {
        Binding(
            get: { prefs[keyPath: keyPath] },
            set: { newValue in
                prefs[keyPath: keyPath] = newValue
                ErrorHandlerService.shared.saveContext(modelContext, caller: caller)
            }
        )
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section("General") {
            Toggle("Haptic Feedback", isOn: $hapticFeedbackEnabled)
        }
    }

    private var interfaceSection: some View {
        Section("Interface") {
            Toggle("Show Onboarding Tips", isOn: prefBinding(\.showOnboardingTips, caller: "AppPreferences.tips"))

            Button("Reset Onboarding Tips") {
                showingResetTipsConfirm = true
            }
        }
    }

    private var golfSection: some View {
        Section("Golf Scoring") {
            Toggle(isOn: $trackDetailedGolfStats) {
                Label("Track Detailed Stats", systemImage: "flag.fill")
            }
            Text("Adds fairway, green-in-regulation, and penalty inputs when scoring a round.")
                .font(.bodySmall)
                .foregroundColor(.secondary)

            Toggle(isOn: $preferShotByShot) {
                Label("Default to Shot-by-Shot", systemImage: "scope")
            }
            Text("New rounds open the shot-by-shot card when you score a hole. You can still switch to Quick on any hole.")
                .font(.bodySmall)
                .foregroundColor(.secondary)
        }
    }

    private var privacyAnalyticsSection: some View {
        Section {
            Toggle("Enable Analytics", isOn: Binding(
                get: { prefs.enableAnalytics },
                set: { newValue in
                    prefs.enableAnalytics = newValue
                    AnalyticsService.shared.setCollection(enabled: newValue)
                    ErrorHandlerService.shared.saveContext(modelContext, caller: "AppPreferences.analytics")
                }
            ))
        } header: {
            Text("Privacy & Analytics")
        } footer: {
            Text("Help improve PlayerPath by sharing anonymous usage data.")
        }
    }
}
