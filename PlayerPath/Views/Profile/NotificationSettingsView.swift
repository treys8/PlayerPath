//
//  NotificationSettingsView.swift
//  PlayerPath
//
//  Notification preferences for game reminders, uploads, and weekly stats.
//

import SwiftUI
import SwiftData

struct NotificationSettingsView: View {
    let athleteId: String?

    @AppStorage("notif_gameReminders") private var gameReminders = true
    @AppStorage("notif_weeklyStats") private var weeklyStats = true
    @AppStorage("notif_uploads") private var uploadNotifications = true
    @Environment(\.modelContext) private var modelContext

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            // Permission status
            permissionStatusSection

            Section("Game Notifications") {
                Toggle("Game Reminders", isOn: $gameReminders)
                    .onChange(of: gameReminders) { _, enabled in
                        let prefs = UserPreferences.shared(in: modelContext)
                        prefs.enableGameReminders = enabled
                        if !enabled {
                            // Cancel any pending game reminder notifications
                            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                                let gameReminderIds = requests
                                    .filter { $0.identifier.hasPrefix("game_reminder_") }
                                    .map { $0.identifier }
                                Task { @MainActor in
                                    PushNotificationService.shared.cancelNotifications(withIdentifiers: gameReminderIds)
                                }
                            }
                        }
                    }
            }
            .disabled(authorizationStatus == .denied)

            Section {
                Toggle("Upload Notifications", isOn: $uploadNotifications)
                    .onChange(of: uploadNotifications) { _, enabled in
                        let prefs = UserPreferences.shared(in: modelContext)
                        prefs.enableUploadNotifications = enabled
                    }
            } header: {
                Text("Videos")
            } footer: {
                Text("Get notified when a video finishes uploading to the cloud.")
            }
            .disabled(authorizationStatus == .denied)

            Section {
                Toggle("Weekly Statistics", isOn: $weeklyStats)
                    .onChange(of: weeklyStats) { _, enabled in
                        if enabled, let athleteId {
                            Task { await PushNotificationService.shared.scheduleWeeklySummary(athleteId: athleteId) }
                        } else if !enabled, let athleteId {
                            Task { @MainActor in
                                PushNotificationService.shared.cancelNotifications(
                                    withIdentifiers: ["weekly_summary_\(athleteId)"]
                                )
                            }
                        }
                    }
            } header: {
                Text("Statistics")
            } footer: {
                Text("Weekly summary delivers every Sunday at 6 PM.")
            }
            .disabled(authorizationStatus == .denied)

            if athleteId == nil {
                Section {
                    NavigationLink {
                        CoachReviewReminderSettingsView()
                    } label: {
                        Label("Review Reminders", systemImage: "bell.badge")
                    }
                } header: {
                    Text("Coach Notifications")
                } footer: {
                    Text("Daily reminder to review session clips.")
                }
                .disabled(authorizationStatus == .denied)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshAuthorizationStatus()
            // Ensure weekly summary is scheduled if enabled
            if weeklyStats, let athleteId {
                await PushNotificationService.shared.scheduleWeeklySummary(athleteId: athleteId)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshAuthorizationStatus() }
            }
        }
    }

    private func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @ViewBuilder
    private var permissionStatusSection: some View {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            EmptyView()

        case .denied:
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Notifications are turned off", systemImage: "bell.slash.fill")
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Your preferences are saved, but you won't receive any alerts until notifications are enabled in iOS Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open iOS Settings") {
                        PushNotificationService.shared.openSettingsIfDenied()
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.brandNavy)
                }
                .padding(.vertical, 4)
            }

        case .notDetermined:
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Notifications not yet enabled", systemImage: "bell.badge.fill")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Enable notifications to receive game reminders, upload alerts, and weekly performance summaries.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Enable Notifications") {
                        Task {
                            _ = await PushNotificationService.shared.requestAuthorization()
                            await refreshAuthorizationStatus()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }

        @unknown default:
            EmptyView()
        }
    }
}
