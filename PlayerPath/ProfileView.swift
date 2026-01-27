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
        static let freeAthleteLimit = 3
        static let signOutDelay: UInt64 = 500_000_000 // 0.5 seconds
    }

    let user: User
    @Binding var selectedAthlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
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

    var body: some View {
        List {
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
        .onAppear {
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

        do {
            try await Task.sleep(nanoseconds: Config.signOutDelay)
            await authManager.signOut()
            Haptics.success()
        } catch {
            Haptics.error()
            // Handle error if needed
        }
    }

    private func updateSortedAthletes() {
        sortedAthletes = (user.athletes ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var canAddMoreAthletes: Bool {
        user.isPremium || (user.athletes ?? []).count < Config.freeAthleteLimit
    }
    
    // MARK: - View Components

    private var quickSearchSection: some View {
        Group {
            if !searchText.isEmpty {
                Section("Search Results") {
                    ForEach(filteredSearchResults, id: \.title) { result in
                        result.link
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
                title: "Seasons",
                icon: "calendar",
                keywords: ["seasons", "manage", "year"],
                link: AnyView(
                    NavigationLink {
                        SeasonsView(athlete: selectedAthlete)
                    } label: {
                        Label("Seasons", systemImage: "calendar")
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
            title: "Security Settings",
            icon: "lock.shield",
            keywords: ["security", "password", "authentication", "biometric", "face id", "touch id"],
            link: AnyView(
                NavigationLink {
                    SecuritySettingsView(user: user)
                } label: {
                    Label("Security Settings", systemImage: "lock.shield")
                }
            )
        ))

        items.append(SearchResult(
            title: "Video Recording",
            icon: "video.badge.gearshape",
            keywords: ["video", "recording", "4k", "quality", "camera", "resolution", "fps"],
            link: AnyView(
                NavigationLink {
                    VideoRecordingSettingsView()
                } label: {
                    Label("Video Recording", systemImage: "video.badge.gearshape")
                }
            )
        ))

        items.append(SearchResult(
            title: "Notifications",
            icon: "bell",
            keywords: ["notifications", "alerts", "push"],
            link: AnyView(
                NavigationLink {
                    NotificationSettingsView()
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

        if user.isPremium {
            items.append(SearchResult(
                title: "Shared Folders",
                icon: "folder.badge.person.crop",
                keywords: ["shared", "folders", "coach", "sharing"],
                link: AnyView(
                    NavigationLink {
                        AthleteFoldersListView()
                    } label: {
                        Label("Shared Folders", systemImage: "folder.badge.person.crop")
                    }
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
                    Label(user.isPremium ? "Subscription" : "Upgrade to Premium", systemImage: user.isPremium ? "crown.fill" : "crown")
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
                    StatisticsExportView()
                } label: {
                    Label("Export Statistics", systemImage: "chart.bar.doc.horizontal")
                }
            )
        ))

        items.append(SearchResult(
            title: "Getting Started",
            icon: "graduationcap.fill",
            keywords: ["onboarding", "tutorial", "getting started", "help", "learn", "guide", "intro", "progress"],
            link: AnyView(
                NavigationLink {
                    OnboardingProgressView()
                } label: {
                    Label("Getting Started", systemImage: "graduationcap.fill")
                }
            )
        ))

        items.append(SearchResult(
            title: "Error Log",
            icon: "exclamationmark.triangle",
            keywords: ["error", "log", "errors", "issues", "problems", "debug", "support", "troubleshoot"],
            link: AnyView(
                NavigationLink {
                    ErrorHistoryView()
                } label: {
                    Label("Error Log", systemImage: "exclamationmark.triangle")
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
            
            if !user.isPremium && (user.athletes ?? []).count >= Config.freeAthleteLimit {
                HStack {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text("Upgrade to Premium for unlimited athletes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if !user.isPremium {
                Text("\((user.athletes ?? []).count) of \(Config.freeAthleteLimit) free athletes used")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var settingsSection: some View {
        Section("Settings") {
            // Coach Sharing Feature
            if user.isPremium {
                NavigationLink {
                    AthleteFoldersListView()
                } label: {
                    Label("Shared Folders", systemImage: "folder.badge.person.crop")
                }
            } else {
                Button {
                    Haptics.warning()
                    showCoachesPremiumAlert = true
                } label: {
                    HStack {
                        Label("Shared Folders", systemImage: "folder.badge.person.crop")
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                            Text("Premium")
                                .font(.caption)
                        }
                        .foregroundColor(.yellow)
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
                SecuritySettingsView(user: user)
            } label: {
                Label("Security Settings", systemImage: "lock.shield")
            }

            NavigationLink {
                VideoRecordingSettingsView()
            } label: {
                Label("Video Recording", systemImage: "video.badge.gearshape")
            }

            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label("Notifications", systemImage: "bell")
            }

            #if DEBUG
            // CloudKit sync testing - monitors iCloud availability and sync status
            NavigationLink {
                CloudKitTestView()
            } label: {
                Label("CloudKit Test", systemImage: "icloud")
                    .foregroundColor(.blue)
            }
            #endif

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

    private var accountSection: some View {
        Section("Account") {
            // Subscription Management
            NavigationLink {
                SubscriptionView(user: user)
            } label: {
                if user.isPremium {
                    Label("Subscription", systemImage: "crown.fill")
                        .badge(Text("Premium").foregroundColor(.yellow))
                } else {
                    Label("Upgrade to Premium", systemImage: "crown")
                }
            }

            // Data Export (GDPR Compliance)
            NavigationLink {
                DataExportView()
            } label: {
                Label("Export My Data", systemImage: "arrow.down.doc")
            }

            // Statistics Export (CSV/PDF Reports)
            NavigationLink {
                StatisticsExportView()
            } label: {
                Label("Export Statistics", systemImage: "chart.bar.doc.horizontal")
            }

            // Error Log (Developer/Support)
            NavigationLink {
                ErrorHistoryView()
            } label: {
                let errorCount = ErrorHandlerService.shared.errorHistory.count
                if errorCount > 0 {
                    Label("Error Log", systemImage: "exclamationmark.triangle")
                        .badge(errorCount)
                } else {
                    Label("Error Log", systemImage: "checkmark.circle")
                }
            }

            // Onboarding Progress
            NavigationLink {
                OnboardingProgressView()
            } label: {
                let progress = OnboardingManager.shared.onboardingProgress
                Label("Getting Started", systemImage: "graduationcap.fill")
                    .badge(Text("\(Int(progress * 100))%"))
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
        // If deleting the selected athlete, select another or none
        if athlete.id == selectedAthlete?.id {
            let remainingAthletes = (user.athletes ?? []).filter { $0.id != athlete.id }
            selectedAthlete = remainingAthletes.first
        }

        modelContext.delete(athlete)

        do {
            try modelContext.save()

            // Track athlete deletion analytics
            AnalyticsService.shared.trackAthleteDeleted(athleteID: athlete.id.uuidString)

            Haptics.success()

            // Clear selection if no athletes remain
            if (user.athletes ?? []).isEmpty {
                selectedAthlete = nil
            }
        } catch {
            print("Failed to delete athlete: \(error)")
            deleteErrorMessage = String(format: ProfileStrings.deleteFailed, error.localizedDescription)
            showDeleteError = true
            Haptics.error()
        }
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
                    print("Profile image updated successfully")
                } catch {
                    print("Failed to save profile image update: \(error)")
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

struct SecuritySettingsView: View {
    let user: User
    @EnvironmentObject var authManager: ComprehensiveAuthManager

    var body: some View {
        Form {
            Section("Account Information") {
                HStack {
                    Text("User ID")
                    Spacer()
                    Text(user.id.uuidString.prefix(8))
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("Email")
                    Spacer()
                    Text(user.email)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Additional security features such as password changes, two-factor authentication, and account management will be available in a future update.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
    }
}

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
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Additional preferences and settings options will be available in a future update.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
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
    @State private var isSaving = false

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
                            print("Profile image updated successfully")
                        } catch {
                            Haptics.error()
                            print("Failed to save profile image update: \(error)")
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            Section("Account Information") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                
                TextField("Email", text: $email)
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
        
        user.username = trimmedUsername
        user.email = trimmedEmail
        
        do {
            try await Task.sleep(nanoseconds: 300_000_000) // Brief delay for UX
            try modelContext.save()
            Haptics.success()
            dismiss()
        } catch {
            print("Failed to save user: \(error)")
            saveErrorMessage = String(format: ProfileStrings.saveFailed, error.localizedDescription)
            showSaveError = true
            Haptics.error()
        }
    }
}

struct NotificationSettingsView: View {
    @State private var gameReminders = true
    @State private var liveGameUpdates = true

    @State private var weeklyStats = true
    @State private var monthlyReports = true

    @State private var achievements = true
    @State private var milestoneAlerts = true

    var body: some View {
        Form {
            Section("Game Notifications") {
                Toggle("Game Reminders", isOn: $gameReminders)
                Toggle("Live Game Updates", isOn: $liveGameUpdates)
            }

            Section("Statistics") {
                Toggle("Weekly Statistics", isOn: $weeklyStats)
                Toggle("Monthly Reports", isOn: $monthlyReports)
            }

            Section("Achievements") {
                Toggle("New Achievements", isOn: $achievements)
                Toggle("Milestone Alerts", isOn: $milestoneAlerts)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
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
            Image(systemName: "sportscourt.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            VStack(spacing: 10) {
                Text("PlayerPath")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version 1.0.0")
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

// MARK: - REMOVED: PaywallView, PaywallFeatureRow, PricingCard
// These deprecated views have been removed in favor of ImprovedPaywallView
// which is used throughout the app (see lines 47, 982)

// MARK: - Athlete Management View

struct AthleteManagementView: View {
    let user: User
    @Binding var selectedAthlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddAthlete = false
    @State private var athletePendingDelete: Athlete?
    @State private var showingDeleteAthleteAlert = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var sortedAthletes: [Athlete] = []

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
                Button(action: { showingAddAthlete = true }) {
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
        // If deleting the selected athlete, select another or none
        if athlete.id == selectedAthlete?.id {
            let remainingAthletes = (user.athletes ?? []).filter { $0.id != athlete.id }
            selectedAthlete = remainingAthletes.first
        }

        modelContext.delete(athlete)

        do {
            try modelContext.save()

            // Track athlete deletion analytics
            AnalyticsService.shared.trackAthleteDeleted(athleteID: athlete.id.uuidString)

            Haptics.success()

            // Clear selection if no athletes remain
            if (user.athletes ?? []).isEmpty {
                selectedAthlete = nil
            }
        } catch {
            print("Failed to delete athlete: \(error)")
            deleteErrorMessage = "Failed to delete athlete: \(error.localizedDescription)"
            showDeleteError = true
            Haptics.error()
        }
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
    @Environment(\.openURL) private var openURL
    @State private var showingPaywall = false

    var body: some View {
        List {
            if user.isPremium {
                premiumActiveSection
                premiumFeaturesSection
                managementSection
            } else {
                upgradeBenefitsSection
                pricingSection
            }
        }
        .sheet(isPresented: $showingPaywall) {
            ImprovedPaywallView(user: user)
        }
    }

    private var premiumActiveSection: some View {
        Section {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Premium Member")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("Thank you for your support!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

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
            .padding(.vertical, 8)
        }
    }

    private var premiumFeaturesSection: some View {
        Section("Your Premium Features") {
            SubscriptionFeatureRow(icon: "person.2.fill", title: "Unlimited Athletes", description: "Add as many athletes as you need")
            SubscriptionFeatureRow(icon: "chart.bar.fill", title: "Advanced Statistics", description: "Detailed performance analytics")
            SubscriptionFeatureRow(icon: "icloud.fill", title: "Cloud Storage", description: "Automatic backup and sync")
            SubscriptionFeatureRow(icon: "video.fill", title: "Unlimited Videos", description: "Record and store unlimited video clips")
            SubscriptionFeatureRow(icon: "star.fill", title: "Highlight Reels", description: "Automatically generated highlights")
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
        Section("Upgrade to Premium") {
            SubscriptionFeatureRow(icon: "person.2.fill", title: "Unlimited Athletes", description: "Currently limited to 3 athletes")
            SubscriptionFeatureRow(icon: "chart.bar.fill", title: "Advanced Statistics", description: "Detailed performance analytics and trends")
            SubscriptionFeatureRow(icon: "icloud.fill", title: "Cloud Storage", description: "Never lose your data with automatic backup")
            SubscriptionFeatureRow(icon: "video.fill", title: "Unlimited Videos", description: "Record and store unlimited video clips")
            SubscriptionFeatureRow(icon: "star.fill", title: "Highlight Reels", description: "Automatically generated highlight videos")
        }
    }

    private var pricingSection: some View {
        Section {
            Button(action: { showingPaywall = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Upgrade to Premium")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        Text("Unlock all features and unlimited athletes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("$9.99")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)

                        Text("per month")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
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

