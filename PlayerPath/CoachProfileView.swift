//
//  CoachProfileView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Profile and settings for coaches
//

import SwiftUI

struct CoachProfileView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var sharedFolderManager = SharedFolderManager.shared
    @ObservedObject private var storeManager = StoreKitManager.shared
    @ObservedObject private var invitationManager = CoachInvitationManager.shared
    @State private var showingSignOutAlert = false
    @State private var isSigningOut = false
    @State private var showingPaywall = false
    @State private var showingInvitations = false
    @State private var showingEditProfile = false
    @State private var coachToAthleteConnectedIDs: Set<String> = []
    
    var body: some View {
            List {
                // Profile Section
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(authManager.userDisplayName ?? "Coach")
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text(authManager.userEmail ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption)
                                Text("Coach Account")
                                    .font(.caption)
                            }
                            .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 8)

                    Button(action: { showingEditProfile = true }) {
                        Label("Edit Profile", systemImage: "pencil")
                    }
                }
                
                // Subscription Section
                Section("Subscription") {
                    HStack {
                        Label("Plan", systemImage: "star.fill")
                        Spacer()
                        Text(authManager.currentCoachTier.displayName)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Athletes", systemImage: "person.3.fill")
                        Spacer()
                        let limit = authManager.coachAthleteLimit
                        if limit == Int.max {
                            Text("\(uniqueAthleteCount) / ∞")
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(uniqueAthleteCount) / \(limit)")
                                .foregroundColor(uniqueAthleteCount > limit ? .red : uniqueAthleteCount >= limit ? .orange : .secondary)
                        }
                    }

                    if uniqueAthleteCount > authManager.coachAthleteLimit && authManager.coachAthleteLimit != Int.max {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("You're over your plan's athlete limit. Upgrade to continue adding athletes.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        showingPaywall = true
                    } label: {
                        Label(authManager.currentCoachTier == .free ? "Upgrade Plan" : "Manage Plan",
                              systemImage: "arrow.up.circle")
                            .foregroundColor(.green)
                    }
                }

                // Stats Section
                Section("Activity") {
                    HStack {
                        Label("Shared Folders", systemImage: "folder.fill")
                        Spacer()
                        Text("\(sharedFolderManager.coachFolders.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Total Videos", systemImage: "video")
                        Spacer()
                        Text("\(totalVideoCount)")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Billing Retry Warning
                if storeManager.isInBillingRetryPeriod {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Payment Failed")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Update your payment method to keep your subscription active.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Fix") {
                                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                        }
                    }
                }

                // Invitations Section
                Section("Invitations") {
                    Button(action: {
                        Haptics.light()
                        showingInvitations = true
                    }) {
                        HStack {
                            Label("Pending Invitations", systemImage: "envelope.badge.fill")
                            Spacer()
                            if invitationManager.pendingInvitationsCount > 0 {
                                Text("\(invitationManager.pendingInvitationsCount)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                // Help & Support Section
                Section("Help & Support") {
                    NavigationLink(destination: FAQView()) {
                        Label("FAQ", systemImage: "questionmark.circle")
                    }
                    NavigationLink(destination: ContactSupportView()) {
                        Label("Contact Support", systemImage: "envelope")
                    }
                }

                // Legal Section
                Section("Legal") {
                    NavigationLink(destination: PrivacyPolicyView()) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    NavigationLink(destination: TermsOfServiceView()) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                }

                // Account Section
                Section("Account") {
                    NavigationLink(destination: AccountDeletionView().environmentObject(authManager)) {
                        Label("Delete Account", systemImage: "trash")
                            .foregroundColor(.red)
                    }

                    Button(action: {
                        Haptics.warning()
                        showingSignOutAlert = true
                    }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
                
                // App Info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                guard let coachID = authManager.userID else { return }
                do {
                    coachToAthleteConnectedIDs = try await FirestoreManager.shared.fetchAcceptedCoachToAthleteAthleteIDs(coachID: coachID)
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "CoachProfile.fetchAthleteIDs", showAlert: false)
                }
            }
            // Listener is pre-started in AuthenticatedFlow; no need to start here.
            .disabled(isSigningOut)
            .overlay {
                if isSigningOut {
                    LoadingOverlay(message: "Signing out...")
                }
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        isSigningOut = true
                        await authManager.signOut()
                        isSigningOut = false
                        Haptics.success()
                    }
                }
                Button("Cancel", role: .cancel) {
                    Haptics.light()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .sheet(isPresented: $showingPaywall) {
                CoachPaywallView()
                    .environmentObject(authManager)
            }
            .navigationDestination(isPresented: $showingInvitations) {
                CoachInvitationsView()
                    .environmentObject(authManager)
                    .onDisappear {
                        Task {
                            guard let coachID = authManager.userID else { return }
                            if let ids = try? await FirestoreManager.shared.fetchAcceptedCoachToAthleteAthleteIDs(coachID: coachID) {
                                coachToAthleteConnectedIDs = ids
                            }
                        }
                    }
            }
            .sheet(isPresented: $showingEditProfile) {
                EditCoachProfileView()
                    .environmentObject(authManager)
            }
    }

    // MARK: - Computed Properties

    private var uniqueAthleteCount: Int {
        var ids = Set(sharedFolderManager.coachFolders.map { $0.ownerAthleteID })
        ids.formUnion(coachToAthleteConnectedIDs)
        return ids.count
    }

    private var totalVideoCount: Int {
        sharedFolderManager.coachFolders.reduce(0) { $0 + ($1.videoCount ?? 0) }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
}

// MARK: - Edit Coach Profile

struct EditCoachProfileView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Your name", text: $displayName)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit {
                            Task { await saveProfile() }
                        }
                }

                Section {
                    Text("Your display name is visible to athletes you coach.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveProfile() }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .alert("Save Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                displayName = authManager.userDisplayName ?? ""
            }
        }
    }

    private func saveProfile() async {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        do {
            try await authManager.updateDisplayName(trimmed)
            await MainActor.run { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isSaving = false
    }
}

// MARK: - Preview

#Preview {
    CoachProfileView()
        .environmentObject(ComprehensiveAuthManager())
}
