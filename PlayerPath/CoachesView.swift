//
//  CoachesView.swift
//  PlayerPath
//
//  Created by Assistant on 11/14/25.
//  Updated with proper SwiftData integration and validation
//

import SwiftUI
import SwiftData

/// View for managing coaches for an athlete
struct CoachesView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    @State private var showingAddCoach = false
    @State private var showingInviteCoach = false
    @State private var showingPremiumAlert = false
    @State private var showingPaywall = false
    @State private var coachToDelete: Coach?
    @State private var showingDeleteConfirmation = false
    @State private var coachToReport: Coach?
    @State private var showingReportConfirmation = false
    @State private var isReinviting = false
    @State private var reinviteError: String?
    @State private var showingReinviteError = false

    // Use @Query to automatically fetch coaches for this athlete
    private var athleteID: UUID

    init(athlete: Athlete) {
        self.athlete = athlete
        self.athleteID = athlete.id
    }

    // Filter coaches by athlete relationship
    private var coaches: [Coach] {
        (athlete.coaches ?? []).sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
    }

    var body: some View {
        Group {
            if coaches.isEmpty {
                EmptyCoachesView(
                    onAddCoach: {
                        Haptics.light()
                        showingAddCoach = true
                    },
                    onInviteCoach: {
                        if authManager.hasCoachingAccess {
                            Haptics.medium()
                            showingInviteCoach = true
                        } else {
                            Haptics.warning()
                            showingPremiumAlert = true
                        }
                    },
                    hasCoachingAccess: authManager.hasCoachingAccess
                )
            } else {
                List {
                    // Invite Coach Banner (Pro)
                    if authManager.hasCoachingAccess {
                        Section {
                            Button {
                                Haptics.medium()
                                showingInviteCoach = true
                            } label: {
                                HStack {
                                    Image(systemName: "person.badge.plus")
                                        .font(.title2)
                                        .foregroundColor(.brandNavy)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Invite a Coach")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text("Share videos and get feedback")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    Section("Your Coaches") {
                        ForEach(coaches) { coach in
                            NavigationLink(destination: CoachDetailView(coach: coach, athlete: athlete)) {
                                CoachRow(coach: coach)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    coachToDelete = coach
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                Button {
                                    coachToReport = coach
                                    showingReportConfirmation = true
                                } label: {
                                    Label("Report", systemImage: "flag")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading) {
                                if coach.isInvitationExpired || coach.lastInvitationStatus == "declined" {
                                    Button {
                                        reinviteCoach(coach)
                                    } label: {
                                        Label("Re-invite", systemImage: "paperplane")
                                    }
                                    .tint(Color.brandNavy)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Coaches", screenClass: "CoachesView") }
        .task { await refreshInvitationStatuses() }
        .navigationTitle("Coaches")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Haptics.light()
                        showingAddCoach = true
                    } label: {
                        Label("Add Coach Contact", systemImage: "person.crop.circle.badge.plus")
                    }

                    Button {
                        if authManager.hasCoachingAccess {
                            Haptics.medium()
                            showingInviteCoach = true
                        } else {
                            Haptics.warning()
                            showingPremiumAlert = true
                        }
                    } label: {
                        Label("Invite Coach to Share", systemImage: "paperplane")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCoach) {
            AddCoachView(athlete: athlete)
        }
        .sheet(isPresented: $showingInviteCoach) {
            InviteCoachSheet(athlete: athlete)
        }
        .sheet(isPresented: $showingPaywall) {
            if let user = authManager.localUser {
                ImprovedPaywallView(user: user)
            }
        }
        .alert("Pro Feature", isPresented: $showingPremiumAlert) {
            Button("Maybe Later", role: .cancel) { }
            Button("Upgrade") {
                showingPaywall = true
            }
        } message: {
            Text("Inviting coaches to share videos requires a Pro subscription. Upgrade to Pro to share your game videos and receive feedback from your coaches.")
        }
        .alert("Delete Coach", isPresented: $showingDeleteConfirmation, presenting: coachToDelete) { coach in
            Button("Cancel", role: .cancel) {
                coachToDelete = nil
            }
            Button("Delete", role: .destructive) {
                deleteCoach(coach)
                coachToDelete = nil
            }
        } message: { coach in
            Text("Are you sure you want to remove \(coach.name) from your coaches?")
        }
        .alert("Report Coach", isPresented: $showingReportConfirmation, presenting: coachToReport) { coach in
            Button("Cancel", role: .cancel) {
                coachToReport = nil
            }
            Button("Report", role: .destructive) {
                reportCoach(coach)
                coachToReport = nil
            }
        } message: { coach in
            Text("Report \(coach.name) for inappropriate behavior? Our team will review this report.")
        }
        .alert("Re-invite Failed", isPresented: $showingReinviteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(reinviteError ?? "Could not send invitation. Check your connection and try again.")
        }
    }

    private func reportCoach(_ coach: Coach) {
        let subject = "Coach Report: \(coach.name)"
        let body = "I would like to report the following coach for inappropriate behavior:\n\nCoach Name: \(coach.name)\nCoach Email: \(coach.email)\n\nDetails:\n[Please describe the issue here]"
        let mailto = "mailto:support@playerpath.app?subject=\(subject)&body=\(body)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: mailto) {
            UIApplication.shared.open(url)
        }
        Haptics.medium()
    }

    private func reinviteCoach(_ coach: Coach) {
        guard !coach.email.isEmpty else {
            Haptics.error()
            return
        }
        guard authManager.hasCoachingAccess else {
            showingPremiumAlert = true
            Haptics.warning()
            return
        }
        guard !isReinviting else { return }

        isReinviting = true
        Task {
            do {
                guard let userID = authManager.userID else { throw NSError(domain: "CoachesView", code: -1) }

                // Re-use existing shared folder if it still exists, otherwise create one
                let folderID: String
                if let existingFolderID = coach.sharedFolderIDs.first,
                   let _ = try await FirestoreManager.shared.fetchSharedFolder(folderID: existingFolderID) {
                    folderID = existingFolderID
                } else {
                    let folderName = "\(athlete.name)'s Videos"
                    folderID = try await SharedFolderManager.shared.createFolder(
                        name: folderName,
                        forAthlete: userID,
                        athleteName: athlete.name,
                        hasCoachingAccess: authManager.hasCoachingAccess
                    )
                    coach.sharedFolderIDs = [folderID]
                }

                // Create a new Firestore invitation document
                _ = try await FirestoreManager.shared.createInvitation(
                    athleteID: userID,
                    athleteName: athlete.name,
                    coachEmail: coach.email.lowercased(),
                    folderID: folderID,
                    folderName: "\(athlete.name)'s Videos"
                )

                // Update local coach record
                coach.invitationSentAt = Date()
                coach.lastInvitationStatus = "pending"
                coach.needsSync = true
                try modelContext.save()
                isReinviting = false
                Haptics.success()
            } catch {
                isReinviting = false
                reinviteError = error.localizedDescription
                showingReinviteError = true
                Haptics.error()
            }
        }
    }

    private func deleteCoach(_ coach: Coach) {
        // Capture Firestore identifiers before deletion clears the object
        let firebaseCoachID = coach.firebaseCoachID
        let sharedFolderIDs = coach.sharedFolderIDs
        let coachFirestoreId = coach.firestoreId
        let userId = athlete.user?.firebaseAuthUid ?? athlete.user?.id.uuidString
        let athleteFirestoreId = athlete.firestoreId

        withAnimation {
            modelContext.delete(coach)
            Task {
                do {
                    try modelContext.save()
                    Haptics.medium()
                } catch {
                    Haptics.error()
                }

                // Revoke Firestore folder access in the background.
                // Silent failures are acceptable — Firestore rules prevent
                // unauthorized access regardless.
                if let coachID = firebaseCoachID, !sharedFolderIDs.isEmpty {
                    for folderID in sharedFolderIDs {
                        do {
                            try await FirestoreManager.shared.removeCoachFromFolder(
                                folderID: folderID,
                                coachID: coachID
                            )
                        } catch {
                            ErrorHandlerService.shared.handle(error, context: "CoachesView.removeCoachFromFolder", showAlert: false)
                        }
                    }
                }

                // Soft-delete coach record in Firestore
                if let coachFirestoreId, let userId, let athleteFirestoreId {
                    await retryAsync {
                        try await FirestoreManager.shared.deleteCoach(
                            userId: userId, athleteFirestoreId: athleteFirestoreId, coachId: coachFirestoreId
                        )
                    }
                }
            }
        }
    }

    /// Checks Firestore for updated invitation statuses and updates local Coach models.
    /// Called when CoachesView appears so the athlete sees when a coach accepts/declines.
    private func refreshInvitationStatuses() async {
        let pendingCoaches = coaches.filter { $0.lastInvitationStatus == "pending" }
        guard !pendingCoaches.isEmpty,
              let athleteUID = authManager.userID else { return }

        do {
            let invitations = try await FirestoreManager.shared.fetchInvitations(forAthleteID: athleteUID)

            for coach in pendingCoaches {
                let email = coach.email.lowercased()
                guard !email.isEmpty else { continue }

                // Find the most recent invitation for this coach email
                if let invitation = invitations
                    .filter({ $0.coachEmail.lowercased() == email })
                    .sorted(by: { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) })
                    .first {

                    switch invitation.status {
                    case .accepted:
                        coach.markInvitationAccepted(
                            firebaseCoachID: invitation.acceptedByCoachID ?? "",
                            folderID: invitation.folderID
                        )
                    case .declined:
                        coach.lastInvitationStatus = "declined"
                    case .pending, .cancelled:
                        break
                    }
                }
            }

            if modelContext.hasChanges {
                try modelContext.save()
            }
        } catch {
            ErrorHandlerService.shared.handle(error, context: "CoachesView.syncCoachData", showAlert: false)
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    guard let container = try? ModelContainer(for: User.self, Athlete.self, Coach.self, configurations: config) else {
        return NavigationStack { Text("Preview unavailable") }
    }

    let athlete = Athlete(name: "Test Athlete")
    container.mainContext.insert(athlete)

    return NavigationStack {
        CoachesView(athlete: athlete)
    }
    .modelContainer(container)
}
