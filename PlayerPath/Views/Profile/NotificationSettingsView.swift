//
//  NotificationSettingsView.swift
//  PlayerPath
//
//  Notification preferences for game reminders, uploads, and weekly stats.
//

import SwiftUI
import SwiftData

struct NotificationSettingsView: View {
    @Environment(\.ppAccent) private var ppAccent
    let athleteId: String?

    // notif_weeklyStats is single-source (UserDefaults only; WeeklySummaryScheduler
    // reads directly from UserDefaults), so @AppStorage stays.
    @AppStorage(NotificationPrefKeys.weeklyStats) private var weeklyStats = true

    // Toggles read directly by services without a ModelContext
    // (GameAlertService, PushNotificationService, UserMainFlow banner gate).
    @AppStorage(NotificationPrefKeys.staleGameReminders) private var staleGameReminders = true
    @AppStorage(NotificationPrefKeys.coachActivity) private var coachActivity = true
    @AppStorage(NotificationPrefKeys.athleteActivity) private var athleteActivity = true
    @AppStorage(NotificationPrefKeys.recruitingViews) private var recruitingViews = true

    // Behavioral re-engagement nudges (local-only; read directly from UserDefaults
    // by their schedulers). Opt-out, default on. (`weeklyStats` above is nudge #4,
    // the weekly recap.)
    @AppStorage(NotificationPrefKeys.clipTaggingReminder) private var clipTaggingReminder = true
    @AppStorage(NotificationPrefKeys.milestoneReminder) private var milestoneReminder = true
    @AppStorage(NotificationPrefKeys.inactivityReminder) private var inactivityReminder = true

    @Environment(\.modelContext) private var modelContext
    @Query private var allPrefs: [UserPreferences]

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Environment(\.scenePhase) private var scenePhase

    /// Coach context is signaled by a nil athleteId at the call site
    /// (`CoachProfileView` passes `athleteId: nil`). Game Reminders and
    /// Weekly Statistics are athlete-scoped and dead/no-op for coaches —
    /// gated off below to avoid showing irrelevant or broken toggles.
    private var isCoach: Bool { athleteId == nil }

    private var isGolfAthlete: Bool {
        guard let athleteId, let uuid = UUID(uuidString: athleteId) else { return false }
        var descriptor = FetchDescriptor<Athlete>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor).first)?.sport == .golf
    }

    private var eventNoun: String { isGolfAthlete ? "Tournament" : "Game" }

    /// Canonical prefs accessor. @Query observes changes reactively; shared(in:)
    /// is a safety net if the singleton somehow isn't present yet (MainAppView
    /// ensures it is on every launch).
    private var prefs: UserPreferences {
        if let first = allPrefs.first { return first }
        return UserPreferences.shared(in: modelContext)
    }

    private var gameRemindersBinding: Binding<Bool> {
        Binding(
            get: { prefs.enableGameReminders },
            set: { enabled in
                prefs.enableGameReminders = enabled
                if enabled {
                    Task { @MainActor in
                        await PushNotificationService.shared.requestAuthorizationIfNeeded()
                        await GameService(modelContext: modelContext).rescheduleAllGameReminders()
                    }
                } else {
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
        )
    }

    private var gameReminderMinutesBinding: Binding<Int> {
        Binding(
            get: { prefs.gameReminderMinutes },
            set: { minutes in
                prefs.gameReminderMinutes = minutes
                Task { @MainActor in
                    await GameService(modelContext: modelContext).rescheduleAllGameReminders()
                }
            }
        )
    }

    private var uploadNotificationsBinding: Binding<Bool> {
        Binding(
            get: { prefs.enableUploadNotifications },
            set: { prefs.enableUploadNotifications = $0 }
        )
    }

    var body: some View {
        Form {
            // Permission status
            permissionStatusSection

            if !isCoach {
                Section {
                    Toggle("\(eventNoun) Reminders", isOn: gameRemindersBinding)

                    if prefs.enableGameReminders {
                        Picker("Remind Me", selection: gameReminderMinutesBinding) {
                            Text("5 minutes before").tag(5)
                            Text("15 minutes before").tag(15)
                            Text("30 minutes before").tag(30)
                            Text("1 hour before").tag(60)
                        }
                    }

                    Toggle("End-of-\(eventNoun) Reminder", isOn: $staleGameReminders)
                        .onChange(of: staleGameReminders) { _, enabled in
                            if !enabled {
                                UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                                    let staleIds = requests
                                        .filter { $0.identifier.hasPrefix("stale-game-") || $0.identifier.hasPrefix("stale-practice-") }
                                        .map { $0.identifier }
                                    Task { @MainActor in
                                        PushNotificationService.shared.cancelNotifications(withIdentifiers: staleIds)
                                    }
                                }
                            }
                        }
                } header: {
                    Text("\(eventNoun) Notifications")
                } footer: {
                    Text("End-of-\(eventNoun) Reminder fires 3.5 hours after a \(eventNoun.lowercased()) starts if it hasn't been ended.")
                }
                .disabled(authorizationStatus == .denied)
            }

            if !isCoach {
                Section {
                    Toggle("Coach Activity", isOn: $coachActivity)
                } header: {
                    Text("Coach Activity")
                } footer: {
                    Text("Notifications when your coach adds a comment or drill card.")
                }
                .disabled(authorizationStatus == .denied)
            }

            if !isCoach {
                Section {
                    Toggle("Profile View Alerts", isOn: $recruitingViews)
                } header: {
                    Text("Recruiting")
                } footer: {
                    Text("Notifications when someone opens your athlete's public recruiting profile.")
                }
                .disabled(authorizationStatus == .denied)
            }

            if isCoach {
                Section {
                    Toggle("Athlete Activity", isOn: $athleteActivity)
                } header: {
                    Text("Athlete Activity")
                } footer: {
                    Text("Notifications when an athlete uploads a new video to your folder.")
                }
                .disabled(authorizationStatus == .denied)
            }

            Section {
                Toggle("Upload Notifications", isOn: uploadNotificationsBinding)
            } header: {
                Text("Videos")
            } footer: {
                Text("Get notified when a video finishes uploading to the cloud.")
            }
            .disabled(authorizationStatus == .denied)

            if !isCoach {
                Section {
                    Toggle("Weekly Statistics", isOn: $weeklyStats)
                        .onChange(of: weeklyStats) { _, enabled in
                            guard let athleteId else { return }
                            if enabled {
                                Task { @MainActor in
                                    if let athlete = findAthlete(id: athleteId) {
                                        await WeeklySummaryScheduler.schedule(for: athlete)
                                    }
                                }
                            } else {
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
            }

            if !isCoach {
                Section {
                    Toggle("Tag Clips Reminder", isOn: $clipTaggingReminder)
                        .onChange(of: clipTaggingReminder) { _, enabled in
                            guard !enabled else { return }
                            Task { @MainActor in
                                await ClipTaggingReminderService.shared.cancelAll()
                            }
                        }

                    Toggle("Milestone Celebrations", isOn: $milestoneReminder)
                        .onChange(of: milestoneReminder) { _, enabled in
                            guard !enabled else { return }
                            Task { @MainActor in
                                await MilestoneReminderService.shared.cancel()
                            }
                        }

                    Toggle("Inactivity Reminder", isOn: $inactivityReminder)
                        .onChange(of: inactivityReminder) { _, enabled in
                            Task { @MainActor in
                                if enabled {
                                    await InactivityReminderService.shared.reschedule()
                                } else {
                                    InactivityReminderService.shared.cancel()
                                }
                            }
                        }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Optional nudges to tag your clips, celebrate new milestones, and check back in after time away.")
                }
                .disabled(authorizationStatus == .denied)
            }

            if isCoach {
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
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshAuthorizationStatus()
            // Ensure weekly summary is scheduled with real stats if enabled
            if weeklyStats, let athleteId, let athlete = findAthlete(id: athleteId) {
                await WeeklySummaryScheduler.schedule(for: athlete)
            }
            await seedActivityPushPreferences()
        }
        .onChange(of: coachActivity) { _, _ in
            Task { await syncActivityPushPreferences() }
        }
        .onChange(of: athleteActivity) { _, _ in
            Task { await syncActivityPushPreferences() }
        }
        .onChange(of: recruitingViews) { _, _ in
            Task { await syncActivityPushPreferences() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshAuthorizationStatus() }
            }
        }
    }

    /// Reconciles the three server-relevant toggles with the account-level values
    /// on first appearance. The toggles are device-local `@AppStorage` (all
    /// defaulting `true`) while Firestore holds one account-level map, so blindly
    /// writing on appear made a second device silently re-enable pushes the user
    /// had turned off on the first one.
    ///
    /// Remote wins for every key that exists; local back-fills only the keys the
    /// account has never stored (the legacy users this sync was added for). A
    /// FAILED read writes nothing — guessing is exactly the clobber being fixed.
    private func seedActivityPushPreferences() async {
        guard let remote = await FirestoreManager.shared.fetchNotificationPreferences() else { return }
        if let value = remote["coachActivity"] { coachActivity = value }
        if let value = remote["athleteActivity"] { athleteActivity = value }
        if let value = remote["recruitingViews"] { recruitingViews = value }
        // Now that locals mirror every stored key, this write is a no-op for those
        // and a back-fill for any that were missing.
        if remote.count < 3 {
            await syncActivityPushPreferences()
        }
    }

    /// Pushes the server-relevant toggles to Firestore so the
    /// `sendPushNotification` Cloud Function can honor them for background pushes.
    private func syncActivityPushPreferences() async {
        await FirestoreManager.shared.syncNotificationPreferences(
            coachActivity: coachActivity,
            athleteActivity: athleteActivity,
            recruitingViews: recruitingViews
        )
    }

    private func findAthlete(id: String) -> Athlete? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let descriptor = FetchDescriptor<Athlete>(predicate: #Predicate { $0.id == uuid })
        return (try? modelContext.fetch(descriptor))?.first
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
                        .font(.headingSmall)
                    Text("Your preferences are saved, but you won't receive any alerts until notifications are enabled in iOS Settings.")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                    Button("Open iOS Settings") {
                        PushNotificationService.shared.openSettingsIfDenied()
                    }
                    .buttonStyle(.bordered)
                    .tint(ppAccent)
                }
                .padding(.vertical, 4)
            }

        case .notDetermined:
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Notifications not yet enabled", systemImage: "bell.badge.fill")
                        .foregroundColor(Theme.warning)
                        .font(.headingSmall)
                    Text(isCoach
                         ? "Enable notifications to receive review reminders, athlete activity, and upload alerts."
                         : "Enable notifications to receive game reminders, upload alerts, and weekly performance summaries.")
                        .font(.bodySmall)
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
