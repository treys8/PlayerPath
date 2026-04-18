//
//  ProfileView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Profile View (Main "More" Tab Root)

struct ProfileView: View {
    // MARK: - Configuration Constants
    private enum Config {
        static let signOutDelay: Duration = .milliseconds(500)
    }

    let user: User
    @Binding var selectedAthlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var storeManager = StoreKitManager.shared
    @State private var showingAddAthlete = false
    @State private var showingSignOutAlert = false
    @State private var athletePendingDelete: Athlete?
    @State private var showingDeleteAthleteAlert = false
    @State private var isSigningOut = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var showingPaywall = false
    @State private var showCoachesPremiumAlert = false
    @State private var sortedAthletes: [Athlete] = []
    @State private var searchText = ""
    @State private var showingQuickSearch = false
    @State private var showingSeasons = false
    @State private var seasonsAthlete: Athlete?
    @State private var isDeletingAthlete = false

    var body: some View {
        List {
            billingRetrySection
            quickSearchSection
            userProfileSection
            athletesSection
            settingsSection
            legalSection
            accountSection
            appVersionSection
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search settings...")
        .tabRootNavigationBar(title: ProfileStrings.title)
        .sheet(isPresented: $showingAddAthlete) {
            AddAthleteView(user: user, selectedAthlete: $selectedAthlete, isFirstAthlete: (user.athletes ?? []).isEmpty)
        }
        .sheet(isPresented: $showingPaywall) {
            ImprovedPaywallView(user: user)
        }
        .alert(ProfileStrings.signOut, isPresented: $showingSignOutAlert) {
            Button(ProfileStrings.cancel, role: .cancel) { }
            Button(ProfileStrings.signOut, role: .destructive) {
                Haptics.warning()
                isSigningOut = true
                Task {
                    await signOut()
                }
            }
        } message: {
            Text(ProfileStrings.signOutConfirmation)
        }
        .alert("Delete Athlete", isPresented: $showingDeleteAthleteAlert) {
            Button(ProfileStrings.cancel, role: .cancel) { athletePendingDelete = nil }
            Button(ProfileStrings.delete, role: .destructive) {
                if let athlete = athletePendingDelete {
                    Haptics.heavy()
                    delete(athlete: athlete)
                    if (user.athletes ?? []).isEmpty { selectedAthlete = nil }
                }
                athletePendingDelete = nil
            }
        } message: {
            Text(ProfileStrings.deleteAthleteConfirmation)
        }
        .alert("Failed to Delete", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage.isEmpty ? ProfileStrings.pleaseRetry : deleteErrorMessage)
        }
        .alert(ProfileStrings.premiumRequired, isPresented: $showCoachesPremiumAlert) {
            Button(ProfileStrings.upgradeToPremium) {
                showingPaywall = true
            }
            Button(ProfileStrings.cancel, role: .cancel) { }
        } message: {
            Text(ProfileStrings.premiumCoachMessage)
        }
        .overlay {
            if isSigningOut {
                LoadingOverlay(message: "Signing out...")
            }
        }
        .task {
            updateSortedAthletes()
        }
        .onChange(of: user.athletes) { _, _ in
            updateSortedAthletes()
        }
        .sheet(isPresented: $showingSeasons) {
            if let athlete = seasonsAthlete {
                NavigationStack {
                    SeasonsView(athlete: athlete)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.presentSeasons)) { notification in
            if let athlete = notification.object as? Athlete {
                seasonsAthlete = athlete
                showingSeasons = true
            }
        }
    }

    // MARK: - Actions
    
    private func signOut() async {
        defer {
            isSigningOut = false
        }

        // Dismiss any open sheets before signing out to prevent
        // them from lingering over the WelcomeFlow
        showingAddAthlete = false
        showingPaywall = false
        showingSeasons = false
        showingQuickSearch = false

        do {
            try await Task.sleep(for: Config.signOutDelay)
            await authManager.signOut()
            Haptics.success()
        } catch {
            ErrorHandlerService.shared.handle(error, context: "ProfileView.signOut", showAlert: false)
        }
    }

    private func updateSortedAthletes() {
        sortedAthletes = (user.athletes ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Use authManager.currentTier (sourced live from StoreKit) instead of the
    /// SwiftData user.tier, which is only written at purchase time and becomes stale
    /// when a subscription expires or renews outside the paywall.
    private var canAddMoreAthletes: Bool {
        (user.athletes ?? []).count < authManager.currentTier.athleteLimit
    }
    
    // MARK: - View Components

    private var quickSearchSection: some View {
        Group {
            if !searchText.isEmpty {
                Section("Search Results") {
                    if filteredSearchResults.isEmpty {
                        Text("No results for \"\(searchText)\"")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredSearchResults, id: \.title) { result in
                            result.link
                        }
                    }
                }
            }
        }
    }

    private var filteredSearchResults: [SearchResult] {
        let query = searchText.lowercased()
        return allSearchableItems.filter { item in
            item.title.lowercased().contains(query) ||
            item.keywords.contains(where: { $0.lowercased().contains(query) })
        }
    }

    private var allSearchableItems: [SearchResult] {
        var items: [SearchResult] = []

        // Athletes Section
        if let selectedAthlete = selectedAthlete {
            items.append(SearchResult(
                title: "Manage Athletes",
                icon: "person.2.fill",
                keywords: ["athletes", "manage", "players"],
                link: AnyView(
                    NavigationLink {
                        AthleteManagementView(user: user, selectedAthlete: $selectedAthlete)
                    } label: {
                        Label("Manage Athletes", systemImage: "person.2.fill")
                    }
                )
            ))

            items.append(SearchResult(
                title: "Manage Seasons",
                icon: "calendar",
                keywords: ["seasons", "manage", "year"],
                link: AnyView(
                    NavigationLink {
                        SeasonManagementView(athlete: selectedAthlete)
                    } label: {
                        Label("Manage Seasons", systemImage: "calendar")
                    }
                )
            ))
        }

        // Settings Section
        items.append(SearchResult(
            title: "Settings",
            icon: "gearshape",
            keywords: ["settings", "preferences", "options"],
            link: AnyView(
                NavigationLink {
                    SettingsView(user: user)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            )
        ))

        items.append(SearchResult(
            title: "Video Recording",
            icon: "video.fill",
            keywords: ["video", "recording", "4k", "quality", "camera", "resolution", "fps"],
            link: AnyView(
                NavigationLink {
                    VideoRecordingSettingsView()
                } label: {
                    Label("Video Recording", systemImage: "video.fill")
                }
            )
        ))

        items.append(SearchResult(
            title: "Notifications",
            icon: "bell",
            keywords: ["notifications", "alerts", "push"],
            link: AnyView(
                NavigationLink {
                    NotificationSettingsView(athleteId: selectedAthlete?.id.uuidString)
                } label: {
                    Label("Notifications", systemImage: "bell")
                }
            )
        ))

        items.append(SearchResult(
            title: "Help & Support",
            icon: "questionmark.circle",
            keywords: ["help", "support", "contact", "faq", "assistance"],
            link: AnyView(
                NavigationLink {
                    HelpSupportView()
                } label: {
                    Label("Help & Support", systemImage: "questionmark.circle")
                }
            )
        ))

        items.append(SearchResult(
            title: "About PlayerPath",
            icon: "info.circle",
            keywords: ["about", "version", "info", "information"],
            link: AnyView(
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About PlayerPath", systemImage: "info.circle")
                }
            )
        ))

        items.append(SearchResult(
            title: "Privacy Policy",
            icon: "hand.raised",
            keywords: ["privacy", "policy", "legal", "data"],
            link: AnyView(
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            )
        ))

        items.append(SearchResult(
            title: "Terms of Use",
            icon: "doc.text",
            keywords: ["terms", "eula", "legal", "use"],
            link: AnyView(
                NavigationLink {
                    TermsOfServiceView()
                } label: {
                    Label("Terms of Use (EULA)", systemImage: "doc.text")
                }
            )
        ))

        if AppFeatureFlags.isCoachEnabled {
            // Resolve a real Athlete once — never synthesise a throwaway record, as the
            // NavigationLink destination is evaluated eagerly and would churn SwiftData.
            let resolvedAthlete = selectedAthlete ?? user.athletes?.first
            if authManager.hasCoachingAccess, let folderAthlete = resolvedAthlete {
                items.append(SearchResult(
                    title: "Shared Folders",
                    icon: "folder.badge.person.crop",
                    keywords: ["shared", "folders", "coach", "sharing"],
                    link: AnyView(
                        NavigationLink {
                            AthleteFoldersListView(userID: authManager.userID, athlete: folderAthlete)
                        } label: {
                            Label("Shared Folders", systemImage: "folder.badge.person.crop")
                        }
                    )
                ))
            } else if !authManager.hasCoachingAccess {
                items.append(SearchResult(
                    title: "Shared Folders",
                    icon: "folder.badge.person.crop",
                    keywords: ["shared", "folders", "coach", "sharing"],
                    link: AnyView(
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack {
                                Label("Shared Folders", systemImage: "folder.badge.person.crop")
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: "crown.fill")
                                        .font(.caption)
                                    Text("Pro")
                                        .font(.caption)
                                }
                                .foregroundColor(.brandNavy)
                            }
                        }
                        .foregroundColor(.primary)
                    )
                ))
            }
        }

        items.append(SearchResult(
            title: "Subscription",
            icon: "crown.fill",
            keywords: ["subscription", "premium", "upgrade", "billing", "payment"],
            link: AnyView(
                NavigationLink {
                    SubscriptionView(user: user)
                } label: {
                    Label(authManager.currentTier == .free ? "Upgrade Plan" : "\(authManager.currentTier.displayName) Plan", systemImage: authManager.currentTier == .free ? "crown" : "crown.fill")
                }
            )
        ))

        items.append(SearchResult(
            title: "Export My Data",
            icon: "arrow.down.doc",
            keywords: ["export", "data", "download", "backup", "gdpr", "json"],
            link: AnyView(
                NavigationLink {
                    DataExportView()
                } label: {
                    Label("Export My Data", systemImage: "arrow.down.doc")
                }
            )
        ))

        items.append(SearchResult(
            title: "Export Statistics",
            icon: "chart.bar.doc.horizontal",
            keywords: ["export", "statistics", "csv", "pdf", "report", "stats", "share", "coach"],
            link: AnyView(
                NavigationLink {
                    StatisticsExportView(athletes: sortedAthletes)
                        .plusRequired()
                } label: {
                    Label("Export Statistics", systemImage: "chart.bar.doc.horizontal")
                }
            )
        ))


        items.append(SearchResult(
            title: "Delete Account",
            icon: "trash",
            keywords: ["delete", "account", "remove", "close", "gdpr"],
            link: AnyView(
                NavigationLink {
                    AccountDeletionView()
                } label: {
                    Label("Delete Account", systemImage: "trash")
                        .foregroundColor(.red)
                }
            )
        ))

        return items
    }

    private var userProfileSection: some View {
        Section {
            UserProfileHeader(user: user)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var athletesSection: some View {
        Section("Athletes") {
            NavigationLink {
                AthleteManagementView(user: user, selectedAthlete: $selectedAthlete)
            } label: {
                Label("Manage Athletes", systemImage: "person.2.fill")
            }

            if let selectedAthlete = selectedAthlete {
                NavigationLink {
                    EditAthleteView(athlete: selectedAthlete)
                } label: {
                    Label("Athlete Settings", systemImage: "slider.horizontal.3")
                }
                .accessibilityHint("Edit settings for \(selectedAthlete.name)")
            } else {
                Label("Athlete Settings", systemImage: "slider.horizontal.3")
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Athlete Settings — select an athlete first")
            }

            if let selectedAthlete = selectedAthlete {
                NavigationLink {
                    SeasonManagementView(athlete: selectedAthlete)
                } label: {
                    Label("Manage Seasons", systemImage: "calendar")
                }
            } else {
                Label("Manage Seasons", systemImage: "calendar")
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Manage Seasons — select an athlete first")
            }

            ForEach(sortedAthletes) { athlete in
                AthleteProfileRow(
                    athlete: athlete,
                    isSelected: athlete.id == selectedAthlete?.id
                ) {
                    selectedAthlete = athlete

                    // Track athlete selection analytics
                    AnalyticsService.shared.trackAthleteSelected(athleteID: athlete.id.uuidString)

                    Haptics.light()
                }
            }
            .onDelete { offsets in
                if let index = offsets.first, index < sortedAthletes.count {
                    athletePendingDelete = sortedAthletes[index]
                    showingDeleteAthleteAlert = true
                }
            }

            Button(action: {
                if canAddMoreAthletes {
                    showingAddAthlete = true
                } else {
                    Haptics.warning()
                    showingPaywall = true
                }
            }) {
                Label("Add Athlete", systemImage: "person.badge.plus")
            }
            .tint(Color.brandNavy)
            
            if (user.athletes ?? []).count >= authManager.currentTier.athleteLimit {
                HStack {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text(AppFeatureFlags.isCoachEnabled
                        ? "Upgrade to Pro for up to 5 athletes"
                        : "Upgrade to Plus for up to \(SubscriptionTier.plus.athleteLimit) athletes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("\((user.athletes ?? []).count) of \(authManager.currentTier.athleteLimit) athlete\(authManager.currentTier.athleteLimit == 1 ? "" : "s") used")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var settingsSection: some View {
        Section("Settings") {
            // Coach Sharing Feature (requires Pro tier + coach features enabled)
            if AppFeatureFlags.isCoachEnabled {
                if authManager.hasCoachingAccess, let folderAthlete = selectedAthlete ?? user.athletes?.first {
                    NavigationLink {
                        AthleteFoldersListView(userID: authManager.userID, athlete: folderAthlete)
                    } label: {
                        Label("Shared Folders", systemImage: "folder.badge.person.crop")
                    }
                } else if !authManager.hasCoachingAccess {
                    Button {
                        Haptics.warning()
                        showingPaywall = true
                    } label: {
                        HStack {
                            Label("Shared Folders", systemImage: "folder.badge.person.crop")
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.caption)
                                Text("Pro")
                                    .font(.caption)
                            }
                            .foregroundColor(.brandNavy)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }

            NavigationLink {
                SettingsView(user: user)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            NavigationLink {
                VideoRecordingSettingsView()
            } label: {
                Label("Video Recording", systemImage: "video.fill")
            }

            NavigationLink {
                NotificationSettingsView(athleteId: selectedAthlete?.id.uuidString)
            } label: {
                Label("Notifications", systemImage: "bell")
            }

            NavigationLink {
                HelpSupportView()
            } label: {
                Label("Help & Support", systemImage: "questionmark.circle")
            }

            NavigationLink {
                AboutView()
            } label: {
                Label("About PlayerPath", systemImage: "info.circle")
            }
        }
    }

    @ViewBuilder private var billingRetrySection: some View {
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
    }

    private var legalSection: some View {
        Section("Legal") {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
            }

            NavigationLink {
                TermsOfServiceView()
            } label: {
                Label("Terms of Use (EULA)", systemImage: "doc.text")
            }
        }
    }

    private var appVersionSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var accountSection: some View {
        Section("Account") {
            // Subscription Management
            NavigationLink {
                SubscriptionView(user: user)
            } label: {
                if authManager.currentTier == .free {
                    Label("Upgrade Plan", systemImage: "crown")
                } else {
                    Label("\(authManager.currentTier.displayName) Plan", systemImage: "crown.fill")
                        .badge(Text(authManager.currentTier.displayName).foregroundColor(.yellow))
                }
            }

            // Data Export (GDPR Compliance)
            NavigationLink {
                DataExportView()
            } label: {
                Label("Export My Data", systemImage: "arrow.down.doc")
            }

            // Statistics Export (CSV/PDF Reports) — Plus+
            NavigationLink {
                StatisticsExportView(athletes: sortedAthletes)
                    .plusRequired()
            } label: {
                Label("Export Statistics", systemImage: "chart.bar.doc.horizontal")
            }


            // Account Deletion (GDPR Compliance)
            NavigationLink {
                AccountDeletionView()
            } label: {
                Label("Delete Account", systemImage: "trash")
                    .foregroundColor(.red)
            }

            Button(ProfileStrings.signOut) {
                Haptics.warning()
                showingSignOutAlert = true
            }
            .disabled(isSigningOut)
            .opacity(isSigningOut ? 0.5 : 1.0)
            .foregroundColor(.error)
            .accessibilityLabel(ProfileStrings.signOut)
            .accessibilityHint("Sign out of your account")
        }
    }

    private func delete(athlete: Athlete) {
        guard !isDeletingAthlete else { return }
        isDeletingAthlete = true
        do {
            try performDeleteAthlete(athlete, selectedAthlete: $selectedAthlete, user: user, modelContext: modelContext)
            Haptics.success()
        } catch {
            ErrorHandlerService.shared.reportError(error, context: "ProfileView.deleteAthlete", message: $deleteErrorMessage, isPresented: $showDeleteError, userMessage: String(format: ProfileStrings.deleteFailed, error.localizedDescription))
        }
        isDeletingAthlete = false
    }
}

struct UserProfileHeader: View {
    let user: User
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 15) {
            EditableProfileImageView(user: user, size: 60) { _ in
                // Save context when profile image is updated
                do {
                    try modelContext.save()
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "ProfileView.saveProfileImage", showAlert: false)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(user.username)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(user.email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let created = user.createdAt {
                    Text("Member since \(created.formatted(.dateTime.year()))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 10)
    }
}

struct AthleteProfileRow: View {
    let athlete: Athlete
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var showingEdit = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack {
                    Image(systemName: "figure.baseball")
                        .font(.title2)
                        .foregroundColor(.brandNavy)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(athlete.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        let gamesCount = (athlete.games ?? []).count
                        let videosCount = (athlete.videoClips ?? []).count
                        HStack {
                            Text("\(gamesCount) \(gamesCount == 1 ? "game" : "games")")
                            Text("•")
                            Text("\(videosCount) \(videosCount == 1 ? "clip" : "clips")")
                            if !athlete.trackStatsEnabled {
                                Text("•")
                                Text("Stats off")
                                    .foregroundColor(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.brandNavy)
                            .accessibilityLabel("Selected")
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Select this athlete")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")

            Button {
                Haptics.light()
                showingEdit = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundColor(.brandNavy)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(athlete.name)")
            .accessibilityHint("Open athlete settings")
        }
        .swipeActions(edge: .leading) {
            Button {
                showingEdit = true
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .tint(.brandNavy)
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack { EditAthleteView(athlete: athlete) }
        }
    }
}

// MARK: - Extracted Sub-Views
// SettingsView, StorageSettingsView, EditAccountView, NotificationSettingsView,
// HelpSupportView, AboutView, ChangePasswordView, AthleteManagementView,
// SubscriptionView, SubscriptionFeatureRow, and SearchResult
// have been moved to Views/Profile/
