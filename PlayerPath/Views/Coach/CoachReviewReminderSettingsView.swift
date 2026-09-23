//
//  CoachReviewReminderSettingsView.swift
//  PlayerPath
//
//  Settings for daily push notification reminders about
//  unreviewed session clips.
//

import SwiftUI

enum ReviewReminderKeys {
    static let enabled = "coachReviewRemindersEnabled"
    static let hour = "coachReviewReminderHour"
    static let minute = "coachReviewReminderMinute"
}

struct CoachReviewReminderSettingsView: View {
    @AppStorage(ReviewReminderKeys.enabled) private var isEnabled = false
    @AppStorage(ReviewReminderKeys.hour) private var reminderHour = 9
    @AppStorage(ReviewReminderKeys.minute) private var reminderMinute = 0

    @State private var selectedTime = Date()
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Toggle("Review Reminders", isOn: $isEnabled)
            } footer: {
                Text("Get a daily notification if you have session clips waiting for review.")
            }

            if isEnabled {
                Section("Reminder Time") {
                    DatePicker(
                        "Time",
                        selection: $selectedTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
            }
        }
        .navigationTitle("Review Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            var components = DateComponents()
            components.hour = reminderHour
            components.minute = reminderMinute
            selectedTime = Calendar.current.date(from: components) ?? Date()
        }
        .onChange(of: isEnabled) { _, enabled in
            if enabled {
                syncTimeAndSchedule()
            } else {
                PushNotificationService.shared.cancelReviewReminder()
            }
        }
        .onChange(of: selectedTime) { _, _ in
            guard isEnabled else { return }
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                syncTimeAndSchedule()
            }
        }
    }

    private func syncTimeAndSchedule() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        reminderHour = components.hour ?? 9
        reminderMinute = components.minute ?? 0
        Task {
            // Route through syncReviewReminder so turning the toggle on with an
            // empty queue doesn't arm a reminder that claims clips are waiting.
            // If the queue is empty it stays disarmed until clips actually
            // arrive and the dashboard's next refresh re-arms it.
            await PushNotificationService.shared.syncReviewReminder(
                pendingCount: PushNotificationService.shared.lastKnownPendingReviewCount
            )
        }
    }
}
