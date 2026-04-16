//
//  AthleteFoldersListView.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  Main view for athletes to see and manage their shared coach folders
//

import SwiftUI

/// Athlete's view of all their shared folders
struct AthleteFoldersListView: View {
    let userID: String?
    let athlete: Athlete
    private var folderManager: SharedFolderManager { .shared }

    /// Folders scoped to the currently-selected athlete.
    /// Nil-athleteUUID folders are intentionally excluded — otherwise they leak across
    /// all athletes on multi-athlete accounts. They're surfaced to the user via
    /// LegacyFolderAssignmentSheet (triggered by FolderAthleteMigrationService).
    private var scopedFolders: [SharedFolder] {
        let selected = athlete.id.uuidString
        return folderManager.athleteFolders.filter { $0.athleteUUID == selected }
    }
    
    enum SheetType: Identifiable {
        case createFolder
        
        var id: String {
            switch self {
            case .createFolder: return "createFolder"
            }
        }
    }
    
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    @State private var activeSheet: SheetType?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isDeletingFolders = false
    @State private var lastFetchDate: Date?
    @State private var showingPaywall = false
    @State private var pendingDeletions: [SharedFolder] = []
    @State private var showingDeleteConfirmation = false
    @State private var sortMode: FolderSortMode = .recentActivity
    @State private var unreadOnly: Bool = false

    enum FolderSortMode: String, CaseIterable, Identifiable {
        case recentActivity = "Recent Activity"
        case mostVideos = "Most Videos"
        case name = "Name"
        var id: String { rawValue }
    }

    private var showSortControl: Bool {
        folderManager.athleteFolders.count >= 5
    }

    private func unreadCount(for folder: SharedFolder) -> Int {
        guard let id = folder.id else { return 0 }
        return activityNotifService.unreadCountByFolder[id] ?? 0
    }

    private var displayedFolders: [SharedFolder] {
        var list = scopedFolders
        if unreadOnly {
            list = list.filter { unreadCount(for: $0) > 0 }
        }
        switch sortMode {
        case .recentActivity:
            return list.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        case .mostVideos:
            return list.sorted { ($0.videoCount ?? 0) > ($1.videoCount ?? 0) }
        case .name:
            return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if folderManager.isLoading {
            ProgressView("Loading folders...")
        } else if scopedFolders.isEmpty {
            emptyState
        } else {
            foldersList
        }
    }

    var body: some View {
        rootContent
            .navigationTitle("Shared Folders")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if showSortControl {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Sort", selection: $sortMode) {
                                ForEach(FolderSortMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            Toggle("Unread only", isOn: $unreadOnly)
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeSheet = .createFolder
                        Haptics.light()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .createFolder:
                    CreateFolderView(athlete: athlete)
                }
            }
            .alert("Folder Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert(deleteAlertTitle, isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { pendingDeletions = [] }
                Button("Delete", role: .destructive) {
                    performDeletion()
                }
            } message: {
                Text(deleteAlertMessage)
            }
            .overlay {
                if isDeletingFolders {
                    deletingOverlay
                }
            }
            .refreshable {
                await loadFolders()
            }
    }

    private var deletingOverlay: some View {
        ProgressView("Deleting...")
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 10)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.person.crop")
                .font(.system(size: 72))
                .foregroundColor(.brandNavy)
            
            Text("No Shared Folders Yet")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Create a folder to share videos with your coach. They'll be able to upload videos and provide feedback.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                activeSheet = .createFolder
                Haptics.light()
            } label: {
                Label("Create Folder", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Folders List
    
    private var hasActiveCoachSharing: Bool {
        folderManager.athleteFolders.contains { !$0.sharedWithCoachIDs.isEmpty }
    }

    private var foldersList: some View {
        List {
            if authManager.currentTier < .pro && hasActiveCoachSharing {
                Section {
                    Button {
                        showingPaywall = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Coach Access Paused")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Text("Your coaches can no longer view these folders. Upgrade to Pro to restore access.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                if displayedFolders.isEmpty && unreadOnly {
                    Text("No folders with unread content.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(displayedFolders) { folder in
                        NavigationLink(destination: AthleteFolderDetailView(folder: folder)) {
                            FolderRow(folder: folder)
                        }
                    }
                    .onDelete(perform: deleteFolders)
                }
            } header: {
                Text("Your folders")
            } footer: {
                Text("Folders are shared with your coaches. They can view and upload videos based on the permissions you set.")
                    .font(.caption)
            }
        }
        .sheet(isPresented: $showingPaywall) {
            if let user = authManager.localUser {
                ImprovedPaywallView(user: user)
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadFolders() async {
        guard let athleteID = userID else {
            errorMessage = "Not authenticated"
            showingError = true
            return
        }
        
        do {
            try await folderManager.loadAthleteFolders(athleteID: athleteID)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private var deleteAlertTitle: String {
        pendingDeletions.count == 1
            ? "Delete '\(pendingDeletions[0].name)'?"
            : "Delete \(pendingDeletions.count) folders?"
    }

    private var deleteAlertMessage: String {
        let totalVideos = pendingDeletions.reduce(0) { $0 + ($1.videoCount ?? 0) }
        if totalVideos == 0 {
            return "This can't be undone. Coach access will be revoked."
        }
        return "This will permanently delete \(totalVideos) video\(totalVideos == 1 ? "" : "s") and revoke coach access. This can't be undone."
    }

    private func deleteFolders(at offsets: IndexSet) {
        let list = displayedFolders
        pendingDeletions = offsets.compactMap { index in
            index < list.count ? list[index] : nil
        }
        guard !pendingDeletions.isEmpty else { return }
        showingDeleteConfirmation = true
    }

    private func performDeletion() {
        let foldersToDelete = pendingDeletions
        pendingDeletions = []

        isDeletingFolders = true
        Task {

            var errors: [String] = []

            for folder in foldersToDelete {
                guard let folderID = folder.id else {
                    errors.append("Folder '\(folder.name)' has no ID")
                    continue
                }

                guard let athleteID = userID else {
                    errors.append("Not authenticated to delete folder '\(folder.name)'")
                    continue
                }

                do {
                    try await folderManager.deleteFolder(folderID: folderID, athleteID: athleteID)
                } catch {
                    errors.append("Failed to delete '\(folder.name)': \(error.localizedDescription)")
                }
            }
            
            await MainActor.run {
                isDeletingFolders = false
                
                if errors.isEmpty {
                    Haptics.success()
                } else {
                    errorMessage = errors.joined(separator: "\n")
                    showingError = true
                    ErrorHandlerService.shared.handle(NSError(domain: "PlayerPath", code: -1, userInfo: [NSLocalizedDescriptionKey: errors.joined(separator: "\n")]), context: "AthleteFoldersListView.deleteFolders", showAlert: false)
                }
            }
        }
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let folder: SharedFolder
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared

    private static let updatedFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var unreadCount: Int {
        guard let folderID = folder.id else { return 0 }
        return activityNotifService.unreadCountByFolder[folderID] ?? 0
    }

    private var updatedLabel: String? {
        guard let date = folder.updatedAt else { return nil }
        // Suppress "just now" churn for freshly-created folders.
        if -date.timeIntervalSinceNow < 60 { return nil }
        return "Updated \(Self.updatedFormatter.localizedString(for: date, relativeTo: Date()))"
    }

    private var folderIcon: String {
        switch folder.folderType {
        case "games":   return "baseball.fill"
        case "lessons": return "video.badge.checkmark"
        default:        return "folder.fill"
        }
    }

    private var folderIconColor: Color {
        switch folder.folderType {
        case "games":   return .brandNavy
        case "lessons": return .green
        default:        return .brandNavy
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Folder icon
            Image(systemName: folderIcon)
                .font(.title2)
                .foregroundColor(folderIconColor)
                .frame(width: 44, height: 44)
                .background(folderIconColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Folder info
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.headline)

                HStack(spacing: 12) {
                    // Video count
                    Label("\(folder.videoCount ?? 0)", systemImage: "video")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Coach count
                    if !folder.sharedWithCoachIDs.isEmpty {
                        Label("\(folder.sharedWithCoachIDs.count)", systemImage: "person.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                }

                if let updatedLabel {
                    Text(updatedLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Unread feedback badge
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Athlete Folder Detail View
// This view shows the same Games/Practices structure as the coach view

/// Detail view for athlete to manage their folder and see videos
struct AthleteFolderDetailView: View {
    let folder: SharedFolder

    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    var body: some View {
        if let athleteID = authManager.userID {
            AthleteFolderDetailContent(folder: folder, athleteID: athleteID)
        } else {
            ContentUnavailableView(
                "Not signed in",
                systemImage: "person.slash",
                description: Text("Sign in to view this folder.")
            )
        }
    }
}

struct AthleteFolderDetailContent: View {
    let folder: SharedFolder
    let athleteID: String

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    @State private var viewModel: CoachFolderViewModel
    private var folderManager: SharedFolderManager { .shared }

    enum SheetType: Identifiable {
        case inviteCoach
        case manageCoaches
        case uploadVideo
        case renameFolder

        var id: String {
            switch self {
            case .inviteCoach: return "inviteCoach"
            case .manageCoaches: return "manageCoaches"
            case .uploadVideo: return "uploadVideo"
            case .renameFolder: return "renameFolder"
            }
        }
    }

    @State private var activeSheet: SheetType?
    @State private var lastFetchDate: Date?

    init(folder: SharedFolder, athleteID: String) {
        self.folder = folder
        self.athleteID = athleteID
        _viewModel = State(initialValue: CoachFolderViewModel(folder: folder))
    }

    private var folderUnreadCount: Int {
        guard let folderID = folder.id else { return 0 }
        return activityNotifService.unreadCountByFolder[folderID] ?? 0
    }

    private func markAllFolderNotificationsRead() {
        guard let folderID = folder.id else { return }
        Task {
            await activityNotifService.markFolderRead(folderID: folderID, forUserID: athleteID)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with folder info
            folderHeader

            // Content: gated behind Pro tier for non-Pro athletes
            if authManager.hasCoachingAccess {
                AthleteVideoListView(
                    folder: folder,
                    videos: viewModel.videos,
                    unreadVideoIDs: activityNotifService.unreadVideoIDs
                ) {
                    await viewModel.loadVideos()
                }
            } else {
                proUpgradeOverlay
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if authManager.hasCoachingAccess {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            activeSheet = .uploadVideo
                        } label: {
                            Label("Share a Video", systemImage: AppIcon.upload)
                        }

                        Button {
                            activeSheet = .inviteCoach
                        } label: {
                            Label("Invite Coach", systemImage: "person.badge.plus")
                        }

                        Button {
                            activeSheet = .manageCoaches
                        } label: {
                            Label("Manage Coaches", systemImage: "person.2.fill")
                        }

                        Button {
                            activeSheet = .renameFolder
                        } label: {
                            Label("Rename Folder", systemImage: "pencil")
                        }

                        if folderUnreadCount > 0 {
                            Divider()
                            Button {
                                markAllFolderNotificationsRead()
                            } label: {
                                Label("Mark All as Read", systemImage: "checkmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .inviteCoach:
                InviteCoachView(folder: folder)
            case .manageCoaches:
                ManageCoachesView(folder: folder)
            case .uploadVideo:
                CoachVideoUploadView(folder: folder, defaultContext: .game)
            case .renameFolder:
                RenameFolderSheet(folder: folder, athleteID: athleteID)
            }
        }
        .task {
            if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < 60 { return }
            await viewModel.loadVideos()
            lastFetchDate = Date()
        }
        .refreshable {
            await viewModel.loadVideos()
        }
    }

    private var proUpgradeOverlay: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            let videoCount = folder.videoCount ?? 0
            if videoCount > 0 {
                Text("\(videoCount) video\(videoCount == 1 ? "" : "s") from your coach")
                    .font(.headline)
            }

            Text("Upgrade to Pro to view shared videos and collaborate with your coach.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                NotificationCenter.default.post(name: .showSubscriptionPaywall, object: nil)
            } label: {
                Text("Upgrade to Pro")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.brandNavy)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var folderHeader: some View {
        HStack(spacing: 12) {
            let count = folder.videoCount ?? viewModel.videos.count
            Label("\(count) video\(count == 1 ? "" : "s")", systemImage: "video")
                .font(.caption)
                .foregroundColor(.secondary)

            let coachCount = folder.sharedWithCoachIDs.count
            Label("\(coachCount) coach\(coachCount == 1 ? "" : "es")", systemImage: "person.fill")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Manage Coaches View

struct ManageCoachesView: View {
    let folder: SharedFolder
    
    @Environment(\.dismiss) private var dismiss
    private var folderManager: SharedFolderManager { .shared }

    @State private var showingRemoveConfirmation = false
    @State private var coachToRemove: String?
    @State private var coachEmailToRemove: String?
    @State private var isRemoving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            List {
                if folder.sharedWithCoachIDs.isEmpty {
                    ContentUnavailableView(
                        "No Coaches Yet",
                        systemImage: "person.2.slash",
                        description: Text("Invite coaches to share this folder with them.")
                    )
                } else {
                    Section {
                        ForEach(folder.sharedWithCoachIDs, id: \.self) { coachID in
                            CoachPermissionRow(
                                folder: folder,
                                coachID: coachID,
                                permissions: folder.getPermissions(for: coachID) ?? .default,
                                onRemove: { loadedEmail in
                                    Haptics.warning()
                                    coachToRemove = coachID
                                    coachEmailToRemove = loadedEmail
                                    showingRemoveConfirmation = true
                                }
                            )
                        }
                    } header: {
                        Text("Shared with")
                    } footer: {
                        Text("Coaches can view and interact with videos based on their permissions.")
                    }
                }
            }
            .navigationTitle("Manage Coaches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isRemoving {
                    ProgressView("Removing coach...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 10)
                }
            }
            .alert("Remove Coach", isPresented: $showingRemoveConfirmation) {
                Button("Cancel", role: .cancel) {
                    coachToRemove = nil
                    coachEmailToRemove = nil
                }
                Button("Remove", role: .destructive) {
                    Haptics.heavy()
                    if let coachID = coachToRemove,
                       let folderID = folder.id {
                        let email = coachEmailToRemove
                        Task {
                            isRemoving = true
                            // Best-effort: if the row never loaded the email
                            // (name came from folder.sharedWithCoachNames),
                            // fetch it now so the revocation record is useful.
                            let resolvedEmail: String
                            if let email, !email.isEmpty {
                                resolvedEmail = email
                            } else if let info = try? await FirestoreManager.shared.fetchCoachInfo(coachID: coachID) {
                                resolvedEmail = info.email
                            } else {
                                resolvedEmail = ""
                            }
                            do {
                                try await folderManager.removeCoachAccess(
                                    coachID: coachID,
                                    coachEmail: resolvedEmail,
                                    fromFolder: folderID,
                                    folderName: folder.name,
                                    athleteID: folder.ownerAthleteID
                                )
                                await MainActor.run {
                                    isRemoving = false
                                    Haptics.success()
                                }
                            } catch {
                                await MainActor.run {
                                    isRemoving = false
                                    errorMessage = error.localizedDescription
                                    showingError = true
                                    ErrorHandlerService.shared.handle(error, context: "ManageCoachesView.removeCoach", showAlert: false)
                                }
                            }
                        }
                    }
                    coachToRemove = nil
                    coachEmailToRemove = nil
                }
            } message: {
                Text("This coach will no longer have access to this folder and its videos.")
            }
            .alert("Folder Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
}

// MARK: - Coach Permission Row

struct CoachPermissionRow: View {
    private static var coachDetailsCache: [String: (name: String, email: String, fetchedAt: Date)] = [:]
    private static let cacheTTL: TimeInterval = 300 // 5 minutes

    /// Clears the coach details cache (call on folder refresh)
    static func clearCache() {
        coachDetailsCache.removeAll()
    }

    let folder: SharedFolder
    let coachID: String
    let permissions: FolderPermissions
    let onRemove: (_ loadedEmail: String?) -> Void

    @State private var coachName: String?
    @State private var coachEmail: String?
    @State private var isLoadingName = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundColor(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    if isLoadingName {
                        Text("Loading...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    } else {
                        Text(coachName ?? "Unknown Coach")
                            .font(.headline)

                        if let email = coachEmail {
                            Text(email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    onRemove(coachEmail)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
            }
            
            // Permissions
            HStack(spacing: 16) {
                PermissionBadge(
                    icon: "arrow.up.circle.fill",
                    title: "Upload",
                    enabled: permissions.canUpload
                )
                
                PermissionBadge(
                    icon: "text.bubble.fill",
                    title: "Comment",
                    enabled: permissions.canComment
                )
                
                PermissionBadge(
                    icon: "trash.fill",
                    title: "Delete",
                    enabled: permissions.canDelete
                )
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .task {
            await loadCoachDetails()
        }
    }

    @MainActor
    private func loadCoachDetails() async {
        guard coachName == nil else { return }

        // Use name stored on the folder document (no network call needed)
        if let storedName = folder.sharedWithCoachNames?[coachID], !storedName.isEmpty {
            self.coachName = storedName
            isLoadingName = false
            return
        }

        if let cached = Self.coachDetailsCache[coachID],
           Date().timeIntervalSince(cached.fetchedAt) < Self.cacheTTL {
            coachName = cached.name
            coachEmail = cached.email
            isLoadingName = false
            return
        }

        do {
            let coachInfo = try await FirestoreManager.shared.fetchCoachInfo(coachID: coachID)
            self.coachName = coachInfo.name
            self.coachEmail = coachInfo.email
            isLoadingName = false
            Self.coachDetailsCache[coachID] = (name: coachInfo.name, email: coachInfo.email, fetchedAt: Date())
        } catch {
            // If fetch fails, show coach ID as fallback
            self.coachName = "Coach \(coachID.prefix(8))"
            self.coachEmail = nil
            isLoadingName = false
        }
    }
}

struct PermissionBadge: View {
    let icon: String
    let title: String
    let enabled: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
        }
        .foregroundColor(enabled ? .green : .secondary)
        .opacity(enabled ? 1.0 : 0.5)
    }
}

// MARK: - Preview

#Preview("Athlete Folders List") {
    NavigationStack {
        AthleteFoldersListView(userID: "preview-user-id", athlete: Athlete(name: "Preview Athlete"))
    }
}

