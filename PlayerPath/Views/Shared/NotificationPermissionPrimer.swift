//
//  NotificationPermissionPrimer.swift
//  PlayerPath
//
//  Explains what notifications are for BEFORE the one-shot iOS dialog.
//
//  New signups already get this context inside onboarding (the athlete primer
//  card on OnboardingBackupView, the coach checklist line on CoachOnboardingFlow's
//  last page). This covers the fallback path those flows never reach: an existing
//  account signing in on a second device or after a reinstall skips every
//  onboarding branch (they all require `isNewUser`) and lands straight on the tab
//  bar, where the system dialog used to fire cold at launch.
//
//  "Not Now" does NOT call iOS — the status stays `.notDetermined`, so the real
//  prompt is still available later from Settings → Notifications.
//

import SwiftUI
import UserNotifications

struct NotificationPermissionPrimer: View {
    /// Coach copy vs athlete copy — the two roles care about different events.
    let isCoach: Bool
    /// Called after the user answers, whichever way, so the caller can dismiss.
    let onFinish: () -> Void

    @Environment(\.ppAccent) private var ppAccent
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    private var reasons: [(icon: String, text: String)] {
        if isCoach {
            return [
                ("video.badge.checkmark", "When an athlete shares new footage to review"),
                ("person.crop.circle.badge.plus", "When an athlete accepts your invitation"),
                ("bell.badge", "A daily reminder for clips still waiting on feedback"),
            ]
        }
        return [
            ("bubble.left.and.text.bubble.right.fill", "When your coach leaves feedback on a clip"),
            ("calendar.badge.clock", "Before a game starts, so you're ready to record"),
            ("trophy.fill", "When you hit a new personal best"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(ppAccent.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(ppAccent)
                    .symbolRenderingMode(.hierarchical)
            }

            Text("Stay in the loop")
                .font(.ppTitle)
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 20)

            Text("PlayerPath can let you know about:")
                .font(.ppBody)
                .foregroundColor(Theme.textSecondary)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(reasons, id: \.icon) { reason in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: reason.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(ppAccent)
                            .frame(width: 26)
                        Text(reason.text)
                            .font(.ppBody)
                            .foregroundColor(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await enable() }
                } label: {
                    Text("Turn On Notifications")
                        .font(.ppBody.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(ppAccent)
                .disabled(isRequesting)

                Button("Not Now") {
                    finish()
                }
                .font(.ppBody)
                .foregroundColor(Theme.textSecondary)
                .disabled(isRequesting)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .interactiveDismissDisabled(isRequesting)
    }

    private func enable() async {
        isRequesting = true
        _ = await PushNotificationService.shared.requestAuthorization()
        isRequesting = false
        finish()
    }

    private func finish() {
        NotificationPermissionPrimer.markShown()
        onFinish()
        dismiss()
    }
}

extension NotificationPermissionPrimer {
    /// Shown-once stamp. The primer is a one-time courtesy on the fallback path;
    /// after it, Settings → Notifications is the way back in (its `.notDetermined`
    /// section already offers an Enable button).
    private static let shownKey = "notif_permissionPrimerShown"

    static func markShown() {
        UserDefaults.standard.set(true, forKey: shownKey)
    }

    /// True when the tab bar should present the primer: iOS has never been asked
    /// AND we haven't already offered on this install.
    ///
    /// Reads `notificationSettings()` live rather than
    /// `PushNotificationService.authorizationStatus`: that cached value is
    /// populated by an async setup task kicked off in the singleton's `init`, so
    /// on a cold launch a tab bar can read it while it still holds its
    /// `.notDetermined` default — which would show this whole sheet to someone
    /// who granted permission months ago.
    static func shouldPresent() async -> Bool {
        guard !UserDefaults.standard.bool(forKey: shownKey) else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .notDetermined
    }
}
