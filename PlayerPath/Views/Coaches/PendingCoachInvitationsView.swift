//
//  PendingCoachInvitationsView.swift
//  PlayerPath
//
//  Shared pieces for showing and acting on incoming coach→athlete invitations.
//  Used by the athlete Coaches page (inline "Invitations" section). The accept
//  flow is delicate — Pro paywall + resume-on-purchase, multi-athlete picker,
//  and a Firestore tier sync before the accept Cloud Function — so it lives here
//  once instead of being duplicated per surface.
//
//  Composition (all hosted inside a `List`):
//    • `CoachInvitationRows`     — a bare `ForEach` of `CoachInvitationCard`s.
//    • `.coachInvitationSheets`  — paywall / picker / error, applied to the List
//                                   so the modal state sits ABOVE the flattened
//                                   rows (a modified `ForEach` stops flattening
//                                   into per-row cards inside a List).
//    • `CoachInvitationActions`  — observable state + accept/decline logic.
//

import SwiftUI
import SwiftData
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "CoachInvitations")

// MARK: - Actions

/// Owns the accept/decline state machine for incoming coach invitations. View
/// dependencies (`authManager`, `modelContext`, the user's athletes) are passed
/// per call so this stays a plain observable object the host view can hold in
/// `@State`.
@MainActor
@Observable
final class CoachInvitationActions {
    var processingInvitationID: String?
    var errorMessage: String?
    var showingPaywall = false
    var pendingInvitationForPicker: CoachToAthleteInvitation?
    /// The invitation the athlete tapped Accept on while below Pro. Held so a
    /// successful upgrade in the paywall can resume the accept automatically.
    var pendingInvitationForPaywall: CoachToAthleteInvitation?
    /// Set by the paywall's purchase callback. The resume runs in the paywall's
    /// `onDismiss` (after the sheet is fully gone) so we never present the athlete
    /// picker while the paywall is still dismissing — which would race two sheets.
    var didPurchaseProForPendingInvite = false

    /// Invoked when the pending list empties after a resolve. The sheet passes
    /// `dismiss`; the Coaches-page section leaves it nil (the section self-clears).
    var onAllResolved: (() -> Void)?

    private var invitationManager: AthleteInvitationManager { .shared }

    func accept(_ invitation: CoachToAthleteInvitation,
                authManager: ComprehensiveAuthManager,
                modelContext: ModelContext,
                athletes: [Athlete]) async {
        guard authManager.hasCoachingAccess else {
            // Queue this invitation so a successful Pro purchase resumes the accept.
            pendingInvitationForPaywall = invitation
            showingPaywall = true
            return
        }
        guard processingInvitationID == nil else {
            log.warning("ACCEPT blocked: already processing \(self.processingInvitationID ?? "nil")")
            return
        }
        guard let uid = authManager.userID, !uid.isEmpty else {
            log.warning("ACCEPT blocked: no userID")
            errorMessage = "Not signed in. Please sign in and try again."
            Haptics.error()
            return
        }

        // Multi-athlete accounts: ask which athlete this invitation is for.
        // Single-athlete (or no athlete yet) accounts skip the picker.
        if athletes.count >= 2 {
            pendingInvitationForPicker = invitation
            return
        }

        await performAccept(invitation, targetAthlete: athletes.first,
                            authManager: authManager, modelContext: modelContext)
    }

    func performAccept(_ invitation: CoachToAthleteInvitation,
                       targetAthlete: Athlete?,
                       authManager: ComprehensiveAuthManager,
                       modelContext: ModelContext) async {
        guard let uid = authManager.userID, !uid.isEmpty else {
            errorMessage = "Not signed in. Please sign in and try again."
            Haptics.error()
            return
        }
        log.debug("ACCEPT starting for invitation \(invitation.id ?? "nil")")
        processingInvitationID = invitation.id

        // Confirm Firestore has our current subscription tier *before* the accept
        // Cloud Function reads it — otherwise a just-upgraded athlete (or a failed
        // sync) would be rejected with a misleading "Pro required" error.
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
                userID: uid,
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
        // processingInvitationID is still set — so the modifier's count `.onChange`
        // skips. Re-check now that the flag is clear to fire onAllResolved.
        if invitationManager.pendingInvitations.isEmpty { onAllResolved?() }
    }

    /// Runs when the paywall opened by the Accept gate is dismissed. If a Pro
    /// purchase completed, resumes the queued accept so the upgrade isn't a dead
    /// end; otherwise drops the queued invitation. Routes straight to
    /// `performAccept` (not back through the gate) so the local tier publisher
    /// doesn't need to have propagated — the server re-validates from the receipt.
    func resumeAfterPaywall(authManager: ComprehensiveAuthManager,
                            modelContext: ModelContext,
                            athletes: [Athlete]) {
        guard let queued = pendingInvitationForPaywall else { return }
        pendingInvitationForPaywall = nil
        guard didPurchaseProForPendingInvite else { return }
        didPurchaseProForPendingInvite = false
        if athletes.count >= 2 {
            // Multi-athlete account: still ask which athlete this invite is for.
            pendingInvitationForPicker = queued
        } else {
            Task {
                await performAccept(queued, targetAthlete: athletes.first,
                                    authManager: authManager, modelContext: modelContext)
            }
        }
    }

    func decline(_ invitation: CoachToAthleteInvitation,
                 authManager: ComprehensiveAuthManager) async {
        guard processingInvitationID == nil else {
            log.warning("DECLINE blocked: already processing \(self.processingInvitationID ?? "nil")")
            return
        }
        guard let uid = authManager.userID, !uid.isEmpty else {
            errorMessage = "Not signed in. Please sign in and try again."
            Haptics.error()
            return
        }
        log.debug("DECLINE starting for invitation \(invitation.id ?? "nil")")
        processingInvitationID = invitation.id

        do {
            try await AthleteInvitationManager.shared.declineInvitation(invitation, userID: uid)
            Haptics.light()
        } catch {
            errorMessage = AthleteInvitationManager.errorMessage(for: error, action: "decline")
            Haptics.error()
        }
        processingInvitationID = nil
        if invitationManager.pendingInvitations.isEmpty { onAllResolved?() }
    }
}

// MARK: - Rows

/// A bare `ForEach` of invitation cards meant to be dropped directly inside a
/// `List` section so each card flattens into its own row. Pair with
/// `.coachInvitationSheets(...)` on the enclosing List.
struct CoachInvitationRows: View {
    let actions: CoachInvitationActions
    let authManager: ComprehensiveAuthManager
    let modelContext: ModelContext
    let athletes: [Athlete]

    private var invitationManager: AthleteInvitationManager { .shared }

    var body: some View {
        ForEach(invitationManager.pendingInvitations) { invitation in
            CoachInvitationCard(
                invitation: invitation,
                isProcessing: actions.processingInvitationID == invitation.id,
                onAccept: {
                    await actions.accept(invitation, authManager: authManager,
                                         modelContext: modelContext, athletes: athletes)
                },
                onDecline: {
                    await actions.decline(invitation, authManager: authManager)
                }
            )
        }
    }
}

// MARK: - Sheets modifier

private struct CoachInvitationSheets: ViewModifier {
    @Bindable var actions: CoachInvitationActions
    let authManager: ComprehensiveAuthManager
    let modelContext: ModelContext
    let athletes: [Athlete]

    private var invitationManager: AthleteInvitationManager { .shared }

    func body(content: Content) -> some View {
        content
            .alert("Invitation Error", isPresented: Binding(
                get: { actions.errorMessage != nil },
                set: { if !$0 { actions.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(actions.errorMessage ?? "")
            }
            .sheet(isPresented: $actions.showingPaywall, onDismiss: {
                actions.resumeAfterPaywall(authManager: authManager,
                                           modelContext: modelContext, athletes: athletes)
            }) {
                if let user = authManager.localUser {
                    ImprovedPaywallView(user: user, requiredTier: .pro) {
                        // Pro purchase completed — flag it; the resume runs in
                        // onDismiss above, after this sheet is fully gone.
                        actions.didPurchaseProForPendingInvite = true
                    }
                }
            }
            .sheet(item: $actions.pendingInvitationForPicker) { invitation in
                AcceptInvitationAthletePickerSheet(
                    invitation: invitation,
                    athletes: athletes
                ) { chosen in
                    actions.pendingInvitationForPicker = nil
                    Task {
                        await actions.performAccept(invitation, targetAthlete: chosen,
                                                    authManager: authManager, modelContext: modelContext)
                    }
                } onCancel: {
                    actions.pendingInvitationForPicker = nil
                }
            }
            .onChange(of: invitationManager.pendingInvitations.count) { _, newCount in
                if newCount == 0 && actions.processingInvitationID == nil {
                    actions.onAllResolved?()
                }
            }
    }
}

extension View {
    /// Attaches the paywall, multi-athlete picker, and error surfaces that back the
    /// Accept/Decline actions in `CoachInvitationRows`. Apply to the `List` (or
    /// other stable container) hosting the rows so the modal state lives above the
    /// flattened rows — never inside the `ForEach`.
    func coachInvitationSheets(_ actions: CoachInvitationActions,
                               authManager: ComprehensiveAuthManager,
                               modelContext: ModelContext,
                               athletes: [Athlete]) -> some View {
        modifier(CoachInvitationSheets(actions: actions, authManager: authManager,
                                       modelContext: modelContext, athletes: athletes))
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
