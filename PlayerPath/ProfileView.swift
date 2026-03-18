//
//  ProfileView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import UIKit
import FirebaseAuth

// MARK: - Profile View (Main "More" Tab Root)

struct ProfileView: View {
    // MARK: - Configuration Constants
    private enum Config {
        static let signOutDelay: UInt64 = 500_000_000 // 0.5 seconds
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
            accountSection
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
            try await Task.sleep(nanoseconds: Config.signOutDelay)
            await authManager.signOut()
            Haptics.success()
        } catch {
            Haptics.error()
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

        if authManager.currentTier == .pro {
            items.append(SearchResult(
                title: "Shared Folders",
                icon: "folder.badge.person.crop",
                keywords: ["shared", "folders", "coach", "sharing"],
                link: AnyView(
                    NavigationLink {
                        AthleteFoldersListView(userID: authManager.userID)
                    } label: {
                        Label("Shared Folders", systemImage: "folder.badge.person.crop")
                    }
                )
            ))
        } else {
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
                            .foregroundColor(.blue)
                        }
                    }
                    .foregroundColor(.primary)
                )
            ))
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
            title: "Cloud Upload Queue",
            icon: "icloud.and.arrow.up",
            keywords: ["cloud", "upload", "sync", "icloud", "storage", "backup", "videos", "pending"],
            link: AnyView(
                NavigationLink {
                    SimpleCloudStorageView()
                } label: {
                    Label("Cloud Upload Queue", systemImage: "icloud.and.arrow.up")
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
            .tint(.blue)
            
            if (user.athletes ?? []).count >= authManager.currentTier.athleteLimit {
                HStack {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text("Upgrade to Pro for up to 5 athletes")
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
            // Coach Sharing Feature (requires Pro tier)
            if authManager.currentTier == .pro {
                NavigationLink {
                    AthleteFoldersListView(userID: authManager.userID)
                } label: {
                    Label("Shared Folders", systemImage: "folder.badge.person.crop")
                }
            } else {
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
                        .foregroundColor(.blue)
                    }
                }
                .foregroundColor(.primary)
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
            deleteErrorMessage = String(format: ProfileStrings.deleteFailed, error.localizedDescription)
            showDeleteError = true
            Haptics.error()
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

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: "figure.baseball")
                    .font(.title2)
                    .foregroundColor(.blue)
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
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .accessibilityLabel("Selected")
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Select this athlete")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

// MARK: - Settings Views

struct SettingsView: View {
    let user: User

    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Text("Username")
                    Spacer()
                    Text(user.username)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Email")
                    Spacer()
                    Text(user.email)
                        .foregroundColor(.secondary)
                }

                NavigationLink {
                    EditAccountView(user: user)
                } label: {
                    Label("Edit Information", systemImage: "pencil")
                }
            }

            Section("Storage") {
                NavigationLink {
                    StorageSettingsView()
                } label: {
                    Label("Manage Storage", systemImage: "internaldrive")
                }

                NavigationLink {
                    SimpleCloudStorageView()
                } label: {
                    Label("Cloud Upload Queue", systemImage: "icloud.and.arrow.up")
                }
            }

            Section("Preferences") {
                NavigationLink {
                    UserPreferencesView()
                } label: {
                    Label("App Preferences", systemImage: "slider.horizontal.3")
                }

                NavigationLink {
                    BiometricSettingsView()
                } label: {
                    Label("Face ID / Touch ID", systemImage: "faceid")
                }
            }

            let provider = Auth.auth().currentUser?.providerData.first?.providerID ?? "email"
            Section("Sign-In Method") {
                HStack {
                    Label(
                        provider == "apple.com" ? "Sign in with Apple" : "Email & Password",
                        systemImage: provider == "apple.com" ? "apple.logo" : "envelope.fill"
                    )
                    Spacer()
                    Text(user.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if provider != "apple.com" {
                    NavigationLink {
                        ChangePasswordView(email: user.email)
                    } label: {
                        Label("Change Password", systemImage: "lock.rotation")
                    }
                }
            }
        }
        .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Settings", screenClass: "ProfileView") }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Storage Settings View
struct StorageSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var storageInfo: StorageInfo?
    @State private var appVideosSize: Int64 = 0
    @State private var appThumbnailsSize: Int64 = 0
    @State private var orphanedFilesCount: Int = 0
    @State private var isLoadingStorage = true
    @State private var isCleaningUp = false
    @State private var cleanupMessage: String?

    var body: some View {
        Form {
            // Device Storage Section
            Section("Device Storage") {
                if let info = storageInfo {
                    VStack(alignment: .leading, spacing: 12) {
                        // Storage level indicator
                        HStack {
                            Image(systemName: storageIcon(for: info.storageLevel))
                                .foregroundColor(storageColor(for: info.storageLevel))
                            Text(storageLabel(for: info.storageLevel))
                                .font(.headline)
                                .foregroundColor(storageColor(for: info.storageLevel))
                        }

                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 8)
                                    .cornerRadius(4)

                                Rectangle()
                                    .fill(storageColor(for: info.storageLevel))
                                    .frame(width: geometry.size.width * (1.0 - info.percentageAvailable), height: 8)
                                    .cornerRadius(4)
                            }
                        }
                        .frame(height: 8)

                        // Storage details
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Available:")
                                Spacer()
                                Text(info.formattedAvailableSpace)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Total:")
                                Spacer()
                                Text(StorageManager.formatBytes(info.totalBytes))
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Estimated Recording Time:")
                                Spacer()
                                Text("\(info.estimatedMinutesOfVideo) min")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                } else {
                    HStack {
                        ProgressView()
                        Text("Loading storage information...")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // App Storage Section
            Section("PlayerPath Storage") {
                HStack {
                    Text("Videos")
                    Spacer()
                    if isLoadingStorage {
                        ProgressView()
                    } else {
                        Text(StorageManager.formatBytes(appVideosSize))
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Thumbnails")
                    Spacer()
                    if isLoadingStorage {
                        ProgressView()
                    } else {
                        Text(StorageManager.formatBytes(appThumbnailsSize))
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Total App Storage")
                    Spacer()
                    if isLoadingStorage {
                        ProgressView()
                    } else {
                        Text(StorageManager.formatBytes(appVideosSize + appThumbnailsSize))
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                }
            }

            // Cleanup Section
            Section {
                if orphanedFilesCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("\(orphanedFilesCount) orphaned file\(orphanedFilesCount == 1 ? "" : "s") found")
                                .font(.subheadline)
                        }

                        Text("These files are taking up space but are not linked to any videos in your library.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    Button {
                        Task {
                            await performCleanup()
                        }
                    } label: {
                        HStack {
                            if isCleaningUp {
                                ProgressView()
                            } else {
                                Image(systemName: "trash")
                            }
                            Text("Clean Up Orphaned Files")
                        }
                    }
                    .disabled(isCleaningUp)
                } else if !isLoadingStorage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("No orphaned files found")
                            .foregroundColor(.secondary)
                    }
                }

                if let message = cleanupMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.vertical, 4)
                }
            } header: {
                Text("Maintenance")
            } footer: {
                Text("Orphaned files are videos that exist on disk but have no database entry. This can happen if app data is restored from backup.")
                    .font(.caption)
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadStorageInfo()
        }
    }

    private func loadStorageInfo() async {
        isLoadingStorage = true

        // Load device storage info
        storageInfo = StorageManager.getStorageInfo()

        // Load app storage usage
        let (videos, thumbnails) = await StorageManager.calculateAppStorageUsage()
        appVideosSize = videos
        appThumbnailsSize = thumbnails

        // Find orphaned files
        let orphanedFiles = await StorageManager.findOrphanedVideoFiles(context: modelContext)
        orphanedFilesCount = orphanedFiles.count

        isLoadingStorage = false
    }

    private func performCleanup() async {
        isCleaningUp = true
        cleanupMessage = nil

        let (filesDeleted, bytesFreed) = await StorageManager.cleanupOrphanedFiles(context: modelContext)

        if filesDeleted > 0 {
            cleanupMessage = "Deleted \(filesDeleted) file\(filesDeleted == 1 ? "" : "s"), freed \(StorageManager.formatBytes(bytesFreed))"
            Haptics.success()

            // Reload storage info
            await loadStorageInfo()
        } else {
            cleanupMessage = "No files to clean up"
        }

        isCleaningUp = false
    }

    private func storageIcon(for level: StorageInfo.StorageLevel) -> String {
        switch level {
        case .good: return "internaldrive"
        case .moderate: return "internaldrive.fill"
        case .low: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private func storageColor(for level: StorageInfo.StorageLevel) -> Color {
        switch level {
        case .good: return .green
        case .moderate: return .blue
        case .low: return .orange
        case .critical: return .red
        }
    }

    private func storageLabel(for level: StorageInfo.StorageLevel) -> String {
        switch level {
        case .good: return "Storage Healthy"
        case .moderate: return "Storage Moderate"
        case .low: return "Storage Low"
        case .critical: return "Storage Critical"
        }
    }
}

struct EditAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var email: String
    let user: User
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showEmailVerificationAlert = false
    @State private var isSaving = false
    @FocusState private var usernameFocused: Bool
    @FocusState private var emailFocused: Bool

    init(user: User) {
        self.user = user
        _username = State(initialValue: user.username)
        _email = State(initialValue: user.email)
    }
    
    private var canSave: Bool {
        let usernameValid = username.trimmed.isNotEmpty
        let emailValid = email.trimmed.isValidEmail
        let hasChanges = username != user.username || email != user.email
        
        return usernameValid && emailValid && hasChanges && !isSaving
    }

    var body: some View {
        Form {
            Section("Profile Picture") {
                HStack {
                    Spacer()
                    EditableProfileImageView(user: user, size: .profileLarge) { _ in
                        do {
                            try modelContext.save()
                            Haptics.light()
                        } catch {
                            Haptics.error()
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            Section("Account Information") {
                TextField("Username", text: $username)
                    .focused($usernameFocused)
                    .submitLabel(.next)
                    .onSubmit { emailFocused = true }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                TextField("Email", text: $email)
                    .focused($emailFocused)
                    .submitLabel(.done)
                    .onSubmit { emailFocused = false }
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                
                if !email.isEmpty && !email.isValidEmail {
                    Label("Please enter a valid email address", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.warning)
                }
            }

            Section {
                Button {
                    Task {
                        await save()
                    }
                } label: {
                    LoadingButtonContent(text: "Save Changes", isLoading: isSaving)
                }
                .disabled(!canSave)
            }
        }
        .navigationTitle("Edit Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Unable to Save", isPresented: $showSaveError) {
            Button("OK") { }
        } message: {
            Text(saveErrorMessage.isEmpty ? ProfileStrings.pleaseRetry : saveErrorMessage)
        }
        .alert("Verify Your Email", isPresented: $showEmailVerificationAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("A verification link was sent to \(email.trimmed). Click it to confirm your new email address.")
        }
    }

    private func save() async {
        let trimmedUsername = username.trimmed
        let trimmedEmail = email.trimmed
        
        // Validate
        let usernameValidation = trimmedUsername.validateUsername()
        guard usernameValidation.isValid else {
            saveErrorMessage = usernameValidation.message
            showSaveError = true
            Haptics.error()
            return
        }
        
        let emailValidation = trimmedEmail.validateEmail()
        guard emailValidation.isValid else {
            saveErrorMessage = emailValidation.message
            showSaveError = true
            Haptics.error()
            return
        }
        
        isSaving = true
        defer { isSaving = false }

        let emailChanged = trimmedEmail != user.email

        // Update Firebase Auth email if changed
        if emailChanged, let firebaseUser = Auth.auth().currentUser {
            do {
                try await firebaseUser.sendEmailVerification(beforeUpdatingEmail: trimmedEmail)
            } catch AuthErrorCode.requiresRecentLogin {
                saveErrorMessage = "For security, please sign out and sign back in before changing your email."
                showSaveError = true
                Haptics.error()
                return
            } catch AuthErrorCode.emailAlreadyInUse {
                saveErrorMessage = "That email address is already associated with another account."
                showSaveError = true
                Haptics.error()
                return
            } catch {
                saveErrorMessage = "Unable to update email: \(error.localizedDescription)"
                showSaveError = true
                Haptics.error()
                return
            }
        }

        user.username = trimmedUsername
        // Don't update user.email locally until the verification link is clicked and
        // Firebase Auth reflects the change. loadUserProfile() syncs email on next sign-in.
        if !emailChanged {
            user.email = trimmedEmail
        }

        do {
            try await Task.sleep(nanoseconds: 300_000_000) // Brief delay for UX
            try modelContext.save()
            Haptics.success()
            if emailChanged {
                showEmailVerificationAlert = true
            } else {
                dismiss()
            }
        } catch {
            saveErrorMessage = String(format: ProfileStrings.saveFailed, error.localizedDescription)
            showSaveError = true
            Haptics.error()
        }
    }
}

struct NotificationSettingsView: View {
    let athleteId: String?

    @AppStorage("notif_gameReminders") private var gameReminders = true
    @AppStorage("notif_liveGame") private var liveGameUpdates = true
    @AppStorage("notif_weeklyStats") private var weeklyStats = true
    @AppStorage("notif_monthlyReports") private var monthlyReports = true
    @AppStorage("notif_achievements") private var achievements = true
    @AppStorage("notif_milestones") private var milestoneAlerts = true
    @AppStorage("notif_uploads") private var uploadNotifications = true

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            // Permission status
            permissionStatusSection

            Section("Game Notifications") {
                Toggle("Game Reminders", isOn: $gameReminders)
                    .onChange(of: gameReminders) { _, enabled in
                        if !enabled {
                            // Cancel any pending game reminder notifications
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
                Toggle("Live Game Updates", isOn: $liveGameUpdates)
            }
            .disabled(authorizationStatus == .denied)

            Section {
                Toggle("Upload Notifications", isOn: $uploadNotifications)
            } header: {
                Text("Videos")
            } footer: {
                Text("Get notified when a video finishes uploading to the cloud.")
            }
            .disabled(authorizationStatus == .denied)

            Section {
                Toggle("Weekly Statistics", isOn: $weeklyStats)
                    .onChange(of: weeklyStats) { _, enabled in
                        if enabled, let athleteId {
                            Task { await PushNotificationService.shared.scheduleWeeklySummary(athleteId: athleteId) }
                        } else if !enabled, let athleteId {
                            Task { @MainActor in
                                PushNotificationService.shared.cancelNotifications(
                                    withIdentifiers: ["weekly_summary_\(athleteId)"]
                                )
                            }
                        }
                    }
                Toggle("Monthly Reports", isOn: $monthlyReports)
            } header: {
                Text("Statistics")
            } footer: {
                Text("Weekly summary delivers every Sunday at 6 PM.")
            }
            .disabled(authorizationStatus == .denied)

            Section("Achievements") {
                Toggle("New Achievements", isOn: $achievements)
                Toggle("Milestone Alerts", isOn: $milestoneAlerts)
            }
            .disabled(authorizationStatus == .denied)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshAuthorizationStatus()
            // Ensure weekly summary is scheduled if enabled
            if weeklyStats, let athleteId {
                await PushNotificationService.shared.scheduleWeeklySummary(athleteId: athleteId)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshAuthorizationStatus() }
            }
        }
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
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Your preferences are saved, but you won't receive any alerts until notifications are enabled in iOS Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open iOS Settings") {
                        PushNotificationService.shared.openSettingsIfDenied()
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
                .padding(.vertical, 4)
            }

        case .notDetermined:
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Notifications not yet enabled", systemImage: "bell.badge.fill")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Enable notifications to receive game reminders, upload alerts, and weekly performance summaries.")
                        .font(.caption)
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

struct HelpSupportView: View {
    var body: some View {
        // Use the comprehensive HelpView created in Views/Help/HelpView.swift
        HelpView()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "figure.baseball")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            VStack(spacing: 10) {
                Text("PlayerPath")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("The ultimate baseball journal for tracking your athletic journey. Record videos, track statistics, and relive your greatest moments.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Text("Made for baseball athletes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Change Password View

struct ChangePasswordView: View {
    let email: String
    @Environment(\.dismiss) private var dismiss
    @State private var isSending = false
    @State private var emailSent = false
    @State private var errorMessage = ""
    @State private var showError = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "lock.rotation")
                        .font(.largeTitle)
                        .foregroundColor(.blue)

                    Text("Change Password")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("We'll send a password reset link to \(email). Follow the link to choose a new password.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            if emailSent {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Email Sent")
                                .font(.headline)
                            Text("Check your inbox at \(email) and follow the link to reset your password.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    Button {
                        Task { await sendReset() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSending {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isSending ? "Sending…" : "Send Reset Email")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSending)
                } footer: {
                    Text("The link expires after 1 hour. Check your spam folder if you don't see it.")
                }
            }
        }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Unable to Send", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func sendReset() async {
        isSending = true
        defer { isSending = false }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            withAnimation { emailSent = true }
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            Haptics.error()
        }
    }
}

// MARK: - REMOVED: PaywallView, PaywallFeatureRow, PricingCard
// These deprecated views have been removed in favor of ImprovedPaywallView
// which is used throughout the app (see lines 47, 982)

// MARK: - Shared Athlete Delete Helper

/// Single source of truth for athlete deletion. Called from both ProfileView and AthleteManagementView.
private func performDeleteAthlete(_ athlete: Athlete, selectedAthlete: Binding<Athlete?>, user: User, modelContext: ModelContext) throws {
    // Capture values before deletion — accessing SwiftData object properties after
    // delete is undefined behavior.
    let athleteID = athlete.id
    if athleteID == selectedAthlete.wrappedValue?.id {
        let remaining = (user.athletes ?? []).filter { $0.id != athleteID }
        selectedAthlete.wrappedValue = remaining.first
    }
    athlete.delete(in: modelContext)
    try modelContext.save()
    AnalyticsService.shared.trackAthleteDeleted(athleteID: athleteID.uuidString)
    if (user.athletes ?? []).isEmpty {
        selectedAthlete.wrappedValue = nil
    }
}

// MARK: - Athlete Management View

struct AthleteManagementView: View {
    let user: User
    @Binding var selectedAthlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingAddAthlete = false
    @State private var showingPaywall = false
    @State private var athletePendingDelete: Athlete?
    @State private var showingDeleteAthleteAlert = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var isDeletingAthlete = false
    @State private var sortedAthletes: [Athlete] = []

    private var canAddMoreAthletes: Bool {
        (user.athletes ?? []).count < authManager.currentTier.athleteLimit
    }

    var body: some View {
        List {
            Section {
                ForEach(sortedAthletes) { athlete in
                    AthleteProfileRow(
                        athlete: athlete,
                        isSelected: athlete.id == selectedAthlete?.id
                    ) {
                        selectedAthlete = athlete
                    }
                }
                .onDelete { offsets in
                    if let index = offsets.first, index < sortedAthletes.count {
                        athletePendingDelete = sortedAthletes[index]
                        showingDeleteAthleteAlert = true
                    }
                }
            }

            Section {
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
                .tint(.blue)
            }
        }
        .navigationTitle("Manage Athletes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAddAthlete) {
            AddAthleteView(user: user, selectedAthlete: $selectedAthlete, isFirstAthlete: (user.athletes ?? []).isEmpty)
        }
        .alert("Delete Athlete", isPresented: $showingDeleteAthleteAlert) {
            Button("Cancel", role: .cancel) { athletePendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let athlete = athletePendingDelete {
                    delete(athlete: athlete)
                }
                athletePendingDelete = nil
            }
        } message: {
            Text("This will delete the athlete and related data. This action cannot be undone.")
        }
        .alert("Failed to Delete", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage.isEmpty ? "Please try again." : deleteErrorMessage)
        }
        .sheet(isPresented: $showingPaywall) {
            ImprovedPaywallView(user: user)
        }
        .onAppear {
            updateSortedAthletes()
        }
        .onChange(of: user.athletes) { _, _ in
            updateSortedAthletes()
        }
    }

    private func updateSortedAthletes() {
        sortedAthletes = (user.athletes ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func delete(athlete: Athlete) {
        guard !isDeletingAthlete else { return }
        isDeletingAthlete = true
        do {
            try performDeleteAthlete(athlete, selectedAthlete: $selectedAthlete, user: user, modelContext: modelContext)
            Haptics.success()
        } catch {
            deleteErrorMessage = String(format: ProfileStrings.deleteFailed, error.localizedDescription)
            showDeleteError = true
            Haptics.error()
        }
        isDeletingAthlete = false
    }
}

// MARK: - Athlete Folders List View (moved)
// Duplicate definition removed. See AthleteFoldersListView.swift for the canonical implementation.

// MARK: - Shared Folders Placeholder Views (removed)
// These placeholder views were removed in favor of the canonical
// implementations: AthleteFolderDetailView and CreateFolderView.

#Preview {
    ProfileView(user: User(username: "test", email: "test@example.com"), selectedAthlete: .constant(nil))
        .environmentObject(ComprehensiveAuthManager())
}

// MARK: - REMOVED: ProfileDetailView and MoreView
// These were duplicates of ProfileView functionality and caused ambiguous init() errors.
// All functionality has been consolidated into the main ProfileView above.

// MARK: - Subscription View

struct SubscriptionView: View {
    let user: User
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var storeManager = StoreKitManager.shared
    @Environment(\.openURL) private var openURL
    @State private var showingPaywall = false

    var body: some View {
        List {
            if authManager.currentTier >= .plus {
                tierActiveSection
                tierFeaturesSection
                managementSection
            } else {
                upgradeBenefitsSection
                pricingSection
            }
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) {
            ImprovedPaywallView(user: user)
        }
    }

    private var tierActiveSection: some View {
        Section {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(authManager.currentTier.displayName) Plan")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(storeManager.isInBillingRetryPeriod
                         ? "There's an issue with your payment."
                         : "Thank you for your support!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if storeManager.isInBillingRetryPeriod {
                    Text("Payment Issue")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .accessibilityLabel("Payment Issue")
                } else {
                    Text("Active")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .accessibilityLabel("Subscription Active")
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var tierFeaturesSection: some View {
        Section("Your \(authManager.currentTier.displayName) Features") {
            SubscriptionFeatureRow(icon: "person.2.fill", title: "\(authManager.currentTier.athleteLimit) Athlete\(authManager.currentTier.athleteLimit == 1 ? "" : "s")", description: "Track up to \(authManager.currentTier.athleteLimit) athlete\(authManager.currentTier.athleteLimit == 1 ? "" : "s")")
            SubscriptionFeatureRow(icon: "internaldrive.fill", title: "\(authManager.currentTier.storageLimitGB) GB Storage", description: "Cloud backup and sync")
            SubscriptionFeatureRow(icon: "chart.bar.fill", title: "Advanced Statistics", description: "Detailed performance analytics")
            SubscriptionFeatureRow(icon: "square.and.arrow.up", title: "Export Reports", description: "CSV and PDF statistics export")
            SubscriptionFeatureRow(icon: "star.fill", title: "Auto Highlights", description: "Automatically generated highlight reels")
            if authManager.currentTier == .pro {
                SubscriptionFeatureRow(icon: "person.badge.shield.checkmark.fill", title: "Coach Sharing", description: "Share videos and get coach feedback")
            }
        }
    }

    private var managementSection: some View {
        Section("Manage Subscription") {
            Button("Manage in App Store") {
                // Open App Store subscription management
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    openURL(url)
                }
            }
            .foregroundColor(.blue)
        }
    }

    private var upgradeBenefitsSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.yellow)

                Text("Unlock Plus & Pro")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("More athletes, cloud storage, highlights, and coach sharing. See full plan details and current pricing below.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var pricingSection: some View {
        Section {
            Button(action: { showingPaywall = true }) {
                HStack {
                    Text("View Plans & Pricing")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }
}

struct SubscriptionFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Search Result Helper

struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let keywords: [String]
    let link: AnyView
}

