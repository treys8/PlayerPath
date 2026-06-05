//
//  AthleteInvitationsBanner.swift
//  PlayerPath
//
//  Shows pending coach invitations to athletes
//

import SwiftUI
import SwiftData
import FirebaseAuth
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "AthleteInvitationsBanner")

struct AthleteInvitationsBanner: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.ppAccent) private var ppAccent
    private var invitationManager: AthleteInvitationManager { .shared }
    @State private var showingInvitations = false

    var body: some View {
        Group {
            if !invitationManager.pendingInvitations.isEmpty {
                Button {
                    Haptics.light()
                    showingInvitations = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(ppAccent.opacity(0.15))
                                .frame(width: 44, height: 44)

                            Image(systemName: "envelope.badge.fill")
                                .font(.title3)
                                .foregroundColor(ppAccent)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(invitationManager.pendingCount) Coach Invitation\(invitationManager.pendingCount == 1 ? "" : "s")")
                                .font(.headingMedium)
                                .foregroundColor(Theme.textPrimary)

                            Text("Tap to view and respond")
                                .font(.bodySmall)
                                .foregroundColor(Theme.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: .cornerXLarge)
                            .fill(ppAccent.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: .cornerXLarge)
                                    .stroke(ppAccent.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingInvitations) {
            AthleteInvitationsSheet()
        }
    }
}

// MARK: - Invitations Sheet

struct AthleteInvitationsSheet: View {
    private var invitationManager: AthleteInvitationManager { .shared }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.modelContext) private var modelContext
    @Query private var allAthletes: [Athlete]

    @State private var processingInvitationID: String?
    @State private var errorMessage: String?
    @State private var showingPaywall = false
    @State private var pendingInvitationForPicker: CoachToAthleteInvitation?
    /// The invitation the athlete tapped Accept on while below Pro. Held so that a
    /// successful upgrade in the paywall can resume the accept automatically instead
    /// of dropping the athlete back with nothing happening.
    @State private var pendingInvitationForPaywall: CoachToAthleteInvitation?
    /// Set by the paywall's purchase callback when a Pro purchase completed. The
    /// resume itself runs in the paywall's `onDismiss` (after the sheet is fully
    /// gone) so we never present the athlete picker while the paywall is still
    /// dismissing — which would race two sheets on the same view.
    @State private var didPurchaseProForPendingInvite = false

    /// Athletes belonging to the currently-signed-in user. Multi-athlete users need to pick one
    /// when accepting a coach invitation (the coach doesn't know which kid the invite is for).
    private var athletesForUser: [Athlete] {
        guard let uid = authManager.userID else { return [] }
        return allAthletes.filter { $0.user?.firebaseAuthUid == uid }
    }

    var body: some View {
        NavigationStack {
            List {
                if invitationManager.pendingInvitations.isEmpty {
                    ContentUnavailableView(
                        "No Pending Invitations",
                        systemImage: "envelope.open",
                        description: Text("You'll see invitations from coaches here")
                    )
                } else {
                    ForEach(invitationManager.pendingInvitations) { invitation in
                        CoachInvitationCard(
                            invitation: invitation,
                            isProcessing: processingInvitationID == invitation.id,
                            onAccept: { await acceptInvitation(invitation) },
                            onDecline: { await declineInvitation(invitation) }
                        )
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .navigationTitle("Coach Invitations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Invitation Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingPaywall, onDismiss: {
                resumeAcceptAfterPaywallIfPurchased()
            }) {
                if let user = authManager.localUser {
                    ImprovedPaywallView(user: user, requiredTier: .pro) {
                        // Pro purchase completed — just flag it. The actual resume
                        // runs in onDismiss above, after this sheet is fully gone.
                        didPurchaseProForPendingInvite = true
                    }
                }
            }
            .sheet(item: $pendingInvitationForPicker) { invitation in
                AcceptInvitationAthletePickerSheet(
                    invitation: invitation,
                    athletes: athletesForUser
                ) { chosen in
                    pendingInvitationForPicker = nil
                    Task { await performAccept(invitation: invitation, targetAthlete: chosen) }
                } onCancel: {
                    pendingInvitationForPicker = nil
                }
            }
            .onChange(of: invitationManager.pendingInvitations.count) { _, newCount in
                if newCount == 0 && processingInvitationID == nil {
                    dismiss()
                }
            }
        }
    }

    private func acceptInvitation(_ invitation: CoachToAthleteInvitation) async {
        guard authManager.hasCoachingAccess else {
            // Queue this invitation so a successful Pro purchase resumes the accept.
            pendingInvitationForPaywall = invitation
            showingPaywall = true
            return
        }
        guard processingInvitationID == nil else {
            log.warning("ACCEPT blocked: already processing \(processingInvitationID ?? "nil")")
            return
        }
        guard let currentUID = authManager.userID, !currentUID.isEmpty else {
            log.warning("ACCEPT blocked: no userID")
            errorMessage = "Not signed in. Please sign in and try again."
            Haptics.error()
            return
        }

        // Multi-athlete accounts: ask which athlete this invitation is for.
        // Single-athlete (or no athlete yet) accounts skip the picker.
        let athletes = athletesForUser
        if athletes.count >= 2 {
            pendingInvitationForPicker = invitation
            return
        }

        await performAccept(invitation: invitation, targetAthlete: athletes.first)
    }

    private func performAccept(invitation: CoachToAthleteInvitation, targetAthlete: Athlete?) async {
        guard let currentUID = authManager.userID, !currentUID.isEmpty else {
            errorMessage = "Not signed in. Please sign in and try again."
            Haptics.error()
            return
        }
        log.debug("ACCEPT starting for invitation \(invitation.id ?? "nil") from coach \(invitation.coachName, privacy: .private)")
        processingInvitationID = invitation.id

        // Confirm Firestore has our current subscription tier *before* the accept
        // Cloud Function reads it — otherwise a just-upgraded athlete (or a failed
        // sync) would be rejected with a misleading "Pro required" error. The sync
        // now throws on failure instead of silently swallowing it.
        do {
            try await authManager.syncSubscriptionTierToFirestoreAndWait()
        } catch {
            log.warning("Tier sync before accept failed: \(error.localizedDescription)")
            errorMessage = "Couldn't verify your subscription. Check your connection and try again."
            Haptics.error()
            processingInvitationID = nil
            return
        }

        do {
            let result = try await AthleteInvitationManager.shared.acceptInvitation(
                invitation,
                userID: currentUID,
                targetAthlete: targetAthlete,
                modelContext: modelContext
            )
            log.info("ACCEPT succeeded for coach: \(result.coachName, privacy: .private)")
            Haptics.success()
        } catch {
            log.warning("ACCEPT failed: \(error.localizedDescription)")
            errorMessage = AthleteInvitationManager.errorMessage(for: error, action: "accept")
            Haptics.error()
        }
        processingInvitationID = nil
        // The manager clears pendingInvitations *during* the await above, while
        // processingInvitationID is still set — so the .onChange dismiss is skipped.
        // Re-check now that the flag is clear to auto-close after the last accept.
        if invitationManager.pendingInvitations.isEmpty { dismiss() }
    }

    /// Runs when the paywall opened by the Accept gate is dismissed. If a Pro
    /// purchase completed, resumes the queued accept so the upgrade isn't a dead
    /// end; otherwise just drops the queued invitation. Runs after the paywall is
    /// fully dismissed, so presenting the athlete picker here can't race the paywall.
    /// Routes straight to `performAccept` (not back through the gate) so the local
    /// tier publisher doesn't need to have propagated yet — the server re-validates
    /// Pro from the App Store receipt during the sync inside `performAccept`.
    private func resumeAcceptAfterPaywallIfPurchased() {
        guard let queued = pendingInvitationForPaywall else { return }
        pendingInvitationForPaywall = nil
        guard didPurchaseProForPendingInvite else {
            // Paywall closed without a qualifying Pro purchase — nothing to resume.
            return
        }
        didPurchaseProForPendingInvite = false
        let athletes = athletesForUser
        if athletes.count >= 2 {
            // Multi-athlete account: still ask which athlete this invite is for.
            pendingInvitationForPicker = queued
        } else {
            Task { await performAccept(invitation: queued, targetAthlete: athletes.first) }
        }
    }

    private func declineInvitation(_ invitation: CoachToAthleteInvitation) async {
        guard processingInvitationID == nil else {
            log.warning("DECLINE blocked: already processing \(processingInvitationID ?? "nil")")
            return
        }
        guard let currentUID = authManager.userID, !currentUID.isEmpty else {
            errorMessage = "Not signed in. Please sign in and try again."
            Haptics.error()
            return
        }
        log.debug("DECLINE starting for invitation \(invitation.id ?? "nil") from coach \(invitation.coachName, privacy: .private)")
        processingInvitationID = invitation.id

        do {
            try await AthleteInvitationManager.shared.declineInvitation(invitation, userID: currentUID)
            Haptics.light()
        } catch {
            errorMessage = AthleteInvitationManager.errorMessage(for: error, action: "decline")
            Haptics.error()
        }
        processingInvitationID = nil
        if invitationManager.pendingInvitations.isEmpty { dismiss() }
    }
}

// MARK: - Invitation Card

struct CoachInvitationCard: View {
    let invitation: CoachToAthleteInvitation
    let isProcessing: Bool
    let onAccept: () async -> Void
    let onDecline: () async -> Void

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Coach info
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(ppAccent.opacity(0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundColor(ppAccent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(invitation.coachName)
                        .font(.headingMedium)
                        .foregroundColor(Theme.textPrimary)

                    Text(invitation.coachEmail)
                        .font(.bodySmall)
                        .foregroundColor(Theme.textSecondary)

                    if let sentAt = invitation.sentAt {
                        Text("Sent \(sentAt.formatted(.relative(presentation: .named)))")
                            .font(.labelSmall)
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }

            // Message if present
            if let message = invitation.message, !message.isEmpty {
                Text(message)
                    .font(.bodyMedium)
                    .foregroundColor(Theme.textSecondary)
                    .padding()
                    .background(Theme.surface)
                    .cornerRadius(.cornerMedium)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    Task { await onDecline() }
                } label: {
                    Text("Decline")
                        .font(.labelLarge)
                        .foregroundColor(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.pillBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.borderless)
                .disabled(isProcessing)

                Button {
                    Task { await onAccept() }
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Accept")
                        }
                    }
                    .font(.headingMedium)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(ppAccent)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.borderless)
                .disabled(isProcessing)
            }
        }
        .padding()
        .background(Theme.card)
        .cornerRadius(.cornerXLarge)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Theme.surface)
    }
}

#Preview {
    AthleteInvitationsBanner()
        .environmentObject(ComprehensiveAuthManager())
        .padding()
}
