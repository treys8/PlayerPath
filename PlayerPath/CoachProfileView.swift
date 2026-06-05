//
//  CoachProfileView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Profile and settings for coaches
//

import SwiftUI
import FirebaseAuth

struct CoachProfileView: View {
    @EnvironmentObject var authManager: ComprehensiveAuthManager
    private var sharedFolderManager: SharedFolderManager { .shared }
    @ObservedObject private var storeManager = StoreKitManager.shared
    private var invitationManager: CoachInvitationManager { .shared }
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    @State private var showingSignOutAlert = false
    @State private var isSigningOut = false
    @State private var showingPaywall = false
    @State private var showingEditProfile = false
    @State private var showingInvitations = false
    @State private var coachToAthleteRefs: [CoachAthleteRef] = []
    @State private var lastConnectedIDsFetch: Date?
    @State var searchText = ""

    // Drives the invitations sheet from deep links (push notification / inbox).
    @Environment(CoachNavigationCoordinator.self) private var coordinator

    var body: some View {
            List {
                coachSearchSection

                // Profile Section
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.brandNavy.opacity(0.1))
                                .frame(width: 60, height: 60)
                            Text(coachInitials)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.brandNavy)
                        }

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
                            .foregroundColor(.brandNavy)
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
                                .foregroundColor(uniqueAthleteCount > limit ? .red : uniqueAthleteCount >= limit ? Theme.warning : .secondary)
                        }
                    }

                    if uniqueAthleteCount > authManager.coachAthleteLimit && authManager.coachAthleteLimit != Int.max {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Theme.warning)
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
                            .foregroundColor(.brandNavy)
                    }
                }

                // Stats Section
                Section("Overview") {
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
                                .foregroundStyle(Theme.warning)
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
                            .tint(Theme.warning)
                            .controlSize(.small)
                        }
                    }
                }

                // Notification Inbox
                Section {
                    NavigationLink(destination: NotificationInboxView()) {
                        HStack {
                            Label("Activity", systemImage: "bell.badge")
                            Spacer()
                            if activityNotifService.unreadCount > 0 {
                                Text("\(activityNotifService.unreadCount)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.red)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                // Invitations Section
                Section("Invitations") {
                    Button {
                        showingInvitations = true
                    } label: {
                        HStack {
                            Label("Pending Invitations", systemImage: "envelope.badge.fill")
                            Spacer()
                            if invitationManager.pendingInvitationsCount > 0 {
                                Text("\(invitationManager.pendingInvitationsCount)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.brandNavy)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                // Settings Section
                Section("Settings") {
                    NavigationLink(destination: UserPreferencesView()) {
                        Label("App Preferences", systemImage: "slider.horizontal.3")
                    }

                    NavigationLink(destination: VideoRecordingSettingsView(role: .coach)) {
                        Label("Video Recording", systemImage: "video.fill")
                    }

                    NavigationLink(destination: StorageSettingsView()) {
                        Label("Manage Storage", systemImage: "internaldrive")
                    }

                    NavigationLink(destination: NotificationSettingsView(athleteId: nil)) {
                        Label("Notifications", systemImage: "bell")
                    }

                    NavigationLink(destination: CoachReviewReminderSettingsView()) {
                        Label("Review Reminders", systemImage: "bell.badge")
                    }

                    let provider = Auth.auth().currentUser?.providerData.first?.providerID ?? "email"
                    if provider != "apple.com" {
                        NavigationLink(destination: ChangePasswordView(email: authManager.userEmail ?? "")) {
                            Label("Change Password", systemImage: "lock")
                        }
                    }
                }

                // Help & Support
                Section("Help & Support") {
                    NavigationLink(destination: HelpSupportView()) {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }

                    NavigationLink(destination: AboutView()) {
                        Label("About PlayerPath", systemImage: "info.circle")
                    }
                }

                // Legal — coaches buy auto-renewing subscriptions, so the EULA
                // and Privacy Policy must be surfaced (not buried in Help articles).
                Section("Legal") {
                    NavigationLink(destination: PrivacyPolicyView()) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }

                    NavigationLink(destination: TermsOfServiceView()) {
                        Label("Terms of Use (EULA)", systemImage: "doc.text")
                    }
                }

                // Account Section
                Section("Account") {
                    NavigationLink(destination: DataExportView().environmentObject(authManager)) {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }

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
                
                // Spread the Word — hidden until a real App Store ID is set.
                if AppStoreConstants.isConfigured {
                    Section("Spread the Word") {
                        if let reviewURL = AppStoreConstants.writeReviewURL {
                            Link(destination: reviewURL) {
                                Label("Rate PlayerPath", systemImage: "star")
                            }
                        }
                        if let shareURL = AppStoreConstants.appStoreURL {
                            ShareLink(item: shareURL) {
                                Label("Share PlayerPath", systemImage: "square.and.arrow.up")
                            }
                        }
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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search settings...")
            .tabRootNavigationBar(title: "More")
            .onAppear {
                // Catch a deep link that set the flag before this view subscribed
                // to onChange (e.g. cold launch from an invitation push).
                if coordinator.pendingShowInvitations {
                    showingInvitations = true
                    coordinator.pendingShowInvitations = false
                }
            }
            .task {
                guard let coachID = authManager.userID else { return }
                do {
                    coachToAthleteRefs = try await FirestoreManager.shared.fetchAcceptedCoachToAthleteRefs(coachID: coachID)
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
            .sheet(isPresented: $showingInvitations, onDismiss: {
                // Re-fetch only when the cached value is stale (>60s) so the
                // connected-athlete count reflects any just-accepted invitations.
                let now = Date()
                if let last = lastConnectedIDsFetch, now.timeIntervalSince(last) < 60 {
                    return
                }
                Task {
                    guard let coachID = authManager.userID else { return }
                    if let refs = try? await FirestoreManager.shared.fetchAcceptedCoachToAthleteRefs(coachID: coachID) {
                        coachToAthleteRefs = refs
                        lastConnectedIDsFetch = Date()
                    }
                }
            }) {
                NavigationStack {
                    CoachInvitationsView()
                        .environmentObject(authManager)
                }
            }
            // Deep links (push notification / inbox) set the coordinator flag;
            // present the sheet and reset the flag so it can fire again.
            .onChange(of: coordinator.pendingShowInvitations) { _, pending in
                if pending {
                    showingInvitations = true
                    coordinator.pendingShowInvitations = false
                }
            }
            .sheet(isPresented: $showingEditProfile) {
                EditCoachProfileView()
                    .environmentObject(authManager)
            }
    }

    // MARK: - Computed Properties

    private var coachInitials: String {
        let name = authManager.userDisplayName ?? "C"
        return name.split(separator: " ").compactMap({ $0.first.map(String.init) }).prefix(2).joined().uppercased()
    }

    private var uniqueAthleteCount: Int {
        SubscriptionGate.connectedAthleteKeys(
            folders: sharedFolderManager.coachFolders,
            invitationRefs: coachToAthleteRefs
        ).count
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
    @State private var email = ""
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showEmailVerificationAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Your name", text: $displayName)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                }

                Section("Email") {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit {
                            Task { await saveProfile() }
                        }
                }

                Section {
                    Text("Your display name is visible to athletes you coach. Changing your email requires confirming a verification link.")
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
            .alert("Verify Your Email", isPresented: $showEmailVerificationAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("A verification link was sent to \(email.trimmingCharacters(in: .whitespacesAndNewlines)). Click it to confirm your new email address.")
            }
            .onAppear {
                displayName = authManager.userDisplayName ?? ""
                email = authManager.userEmail ?? ""
            }
        }
    }

    private func saveProfile() async {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let emailChanged = trimmedEmail.lowercased() != (authManager.userEmail ?? "").lowercased()

        // Email change goes through Firebase's verify-before-update flow (mirrors
        // the athlete EditAccountView). Firestore email syncs on next sign-in.
        if emailChanged {
            let validation = trimmedEmail.validateEmail()
            guard validation.isValid else {
                errorMessage = validation.message
                showError = true
                return
            }
            guard let firebaseUser = Auth.auth().currentUser else {
                errorMessage = "You must be signed in to change your email."
                showError = true
                return
            }
            do {
                try await firebaseUser.sendEmailVerification(beforeUpdatingEmail: trimmedEmail)
            } catch AuthErrorCode.requiresRecentLogin {
                errorMessage = "For security, please sign out and sign back in before changing your email."
                showError = true
                return
            } catch AuthErrorCode.emailAlreadyInUse {
                errorMessage = "That email address is already associated with another account."
                showError = true
                return
            } catch {
                errorMessage = "Unable to update email: \(error.localizedDescription)"
                showError = true
                return
            }
        }

        if trimmedName != (authManager.userDisplayName ?? "") {
            do {
                try await authManager.updateDisplayName(trimmedName)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                return
            }
        }

        if emailChanged {
            showEmailVerificationAlert = true
        } else {
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    CoachProfileView()
        .environmentObject(ComprehensiveAuthManager())
}
