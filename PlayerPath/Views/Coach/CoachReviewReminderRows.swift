//
//  CoachReviewReminderRows.swift
//  PlayerPath
//
//  Inline rows for the coach's daily "clips waiting for review" reminder.
//  Hosted inside NotificationSettingsView's coach Activity section, so the
//  parent's theme and permission-denied `.disabled` apply.
//

import SwiftUI

struct CoachReviewReminderRows: View {
    @AppStorage(ReviewReminderKeys.enabled) private var isEnabled = false
    @AppStorage(ReviewReminderKeys.hour) private var reminderHour = 9
    @AppStorage(ReviewReminderKeys.minute) private var reminderMinute = 0

    @State private var selectedTime = Date()
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        // Modifiers hang off the Toggle (always present), not a Group — a Group
        // would fan them out to every row and run onAppear once per child.
        Toggle("Review Reminders", isOn: $isEnabled)
            .onAppear {
                var components = DateComponents()
                components.hour = reminderHour
                components.minute = reminderMinute
                selectedTime = Calendar.current.date(from: components) ?? Date()
            }
            .onChange(of: isEnabled) { _, enabled in
                if enabled {
                    syncTimeAndSchedule(requestAuthorization: true)
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

        if isEnabled {
            DatePicker(
                "Remind Me At",
                selection: $selectedTime,
                displayedComponents: .hourAndMinute
            )
        }
    }

    private func syncTimeAndSchedule(requestAuthorization: Bool = false) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        reminderHour = components.hour ?? 9
        reminderMinute = components.minute ?? 0
        Task {
            // The section is only disabled on `.denied`, so a not-yet-asked coach
            // can flip this on — prompt first, or scheduling silently no-ops.
            if requestAuthorization {
                await PushNotificationService.shared.requestAuthorizationIfNeeded()
            }
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
