//
//  CoachFolderDetailView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Detailed view of a shared folder. Games folders show a flat video list; lessons folders show My Drafts / Shared tabs.
//

import SwiftUI

/// Shows the contents of a shared folder. Games folders display a flat video list; lessons folders use My Drafts / Shared tabs.
struct CoachFolderDetailView: View {
    let folder: SharedFolder

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachNavigationCoordinator.self) private var coordinator
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    @State private var viewModel: CoachFolderViewModel
    @State private var selectedTab: FolderTab
    @State private var showingUploadSheet = false
    @State private var verifiedFolder: SharedFolder?
    @State private var permissionError: String?
    @State private var showingPermissionError = false
    @State private var isRefreshingPermissions = false
    @State private var lastRefreshed: Date?
    @State private var showingLeaveConfirmation = false
    @State private var isLeaving = false
    @State private var lastFetchDate: Date?
    @State private var selectedTagFilter: String?
    @State private var showingTagEditor = false
    @State private var editingVideoTags: CoachVideoItem?
    @State private var editingTags: [String] = []
    @State private var editingDrillType: String?
    @State private var tagEditorDidSave = false
    @State private var cachedAvailableTags: [String] = []
    @State private var reviewingClip: CoachVideoItem?
    @State private var isSharingAll = false
    @State private var shareProgress: (current: Int, total: Int)?
    @State private var showingQuickRecord = false
    @State private var showingActiveSessionAlert = false
    @State private var gamesFilter: GamesFolderFilter = .needsReview
    private var archiveManager: CoachFolderArchiveManager { .shared }

    init(folder: SharedFolder, initialTab: FolderTab = .review) {
        self.folder = folder
        _viewModel = State(initialValue: CoachFolderViewModel(folder: folder))
        _verifiedFolder = State(initialValue: folder)
        _selectedTab = State(initialValue: initialTab)
    }

    /// Tabs only used for lessons folders. Games folders show a flat list.
    enum FolderTab: String, CaseIterable {
        case review = "My Drafts"
        case shared = "Shared"
    }

    /// Segmented filter shown above the games folder list. Defaults to
    /// `.needsReview` so coaches land on their queue rather than the backlog.
    enum GamesFolderFilter: String, CaseIterable {
        case needsReview = "Needs My Review"
        case all = "All Clips"
    }

    private var isLessonsFolder: Bool {
        folder.folderType == "lessons"
    }

    var body: some View {
        navigationWrappedContent
            .modifier(FolderSheetsModifier(
                showingUploadSheet: $showingUploadSheet,
                showingTagEditor: $showingTagEditor,
                editingTags: $editingTags,
                editingDrillType: $editingDrillType,
                tagEditorDidSave: $tagEditorDidSave,
                verifiedFolder: verifiedFolder,
                editingVideoTags: editingVideoTags,
                viewModel: viewModel
            ))
            .modifier(FolderDialogsModifier(
                showingPermissionError: $showingPermissionError,
                showingLeaveConfirmation: $showingLeaveConfirmation,
                permissionError: permissionError,
                folderName: folder.name,
                onLeave: { Task { await leaveFolder() } }
            ))
            .fullScreenCover(item: $reviewingClip) { clip in
                ClipReviewSheet(
                    video: clip,
                    folder: folder,
                    onShared: { Task { await viewModel.loadVideos() } },
                    onDiscarded: { Task { await viewModel.loadVideos() } }
                )
            }
            .fullScreenCover(isPresented: $showingQuickRecord, onDismiss: {
                Task { await viewModel.loadVideos() }
            }) {
                if let session = CoachSessionManager.shared.activeSession {
                    DirectCameraRecorderView(
                        coachContext: CoachSessionContext(sessionID: session.id ?? "", session: session)
                    )
                } else {
                    Color.clear.onAppear { showingQuickRecord = false }
                }
            }
            .alert("Session In Progress", isPresented: $showingActiveSessionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please end your current session before starting a new recording.")
            }
            .task { await initialLoad() }
            .onChange(of: viewModel.allVideos) { _, _ in refreshAvailableTags() }
            .onChange(of: viewModel.sharedVideos) { _, _ in refreshAvailableTags() }
            .onChange(of: viewModel.reviewVideos) { _, _ in refreshAvailableTags() }
            .disabled(isLeaving)
            .overlay { leavingOverlay }
    }

    private var navigationWrappedContent: some View {
        folderContent
            .navigationTitle(folder.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                Task { await refreshPermissions() }
            } label: {
                if isRefreshingPermissions {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.brandNavy)
                }
            }
            .disabled(isRefreshingPermissions)
            .help("Refresh permissions")
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            trailingMenu
        }
    }

    private var trailingMenu: some View {
        Menu {
            if isLessonsFolder && canUpload {
                Button {
                    quickRecord()
                } label: {
                    Label("Record Clip", systemImage: "record.circle")
                }

                Button {
                    showingUploadSheet = true
                } label: {
                    Label("Upload Video", systemImage: AppIcon.upload)
                }
            }

            let folderID = folder.id ?? ""
            let archived = archiveManager.isArchived(folderID)
            Button {
                if archived {
                    archiveManager.unarchive(folderID: folderID)
                } else {
                    archiveManager.archive(folderID: folderID)
                    dismiss()
                }
                Haptics.light()
            } label: {
                Label(
                    archived ? "Unarchive Folder" : "Archive Folder",
                    systemImage: archived ? "archivebox" : "archivebox.fill"
                )
            }

            Button(role: .destructive) {
                showingLeaveConfirmation = true
            } label: {
                Label("Leave Folder", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(.primary)
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var leavingOverlay: some View {
        if isLeaving {
            ZStack {
                Color(.systemBackground).opacity(0.8).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Leaving folder...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Initial Load

    private func initialLoad() async {
        // Check if coordinator requested a specific tab for THIS folder (e.g., from dashboard "Review Clips")
        if let pending = coordinator.pendingFolderTab, pending.folderID == folder.id {
            selectedTab = pending.tab
            coordinator.pendingFolderTab = nil
        }

        // Always clear this folder's unread badge on open, even if we skip the
        // video refetch below. Without this, a second device opening the folder
        // within the 60s dedup window keeps showing stale unread indicators.
        if let folderID = folder.id, let userID = authManager.userID {
            await activityNotifService.markFolderRead(folderID: folderID, forUserID: userID)
        }

        if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < 60 { return }
        await viewModel.loadVideos()
        await verifyPermissionsInBackground()
        lastFetchDate = Date()
    }

    // MARK: - Folder Content

    private var folderContent: some View {
        VStack(spacing: 0) {
            if let listenerError = SharedFolderManager.shared.listenerError {
                Label(listenerError, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
            }

            FolderInfoHeader(folder: folder, videoCount: viewModel.videos.count, lastRefreshed: lastRefreshed)

            if isLessonsFolder {
                Picker("View", selection: $selectedTab) {
                    ForEach(FolderTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedTab) { _, _ in
                    selectedTagFilter = nil
                    refreshAvailableTags()
                }
            } else {
                Picker("Filter", selection: $gamesFilter) {
                    ForEach(GamesFolderFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: gamesFilter) { _, _ in
                    selectedTagFilter = nil
                    refreshAvailableTags()
                }
            }

            if !cachedAvailableTags.isEmpty {
                VideoTagFilterBar(
                    tags: cachedAvailableTags,
                    selectedTag: $selectedTagFilter
                )
            }

            Group {
                if isLessonsFolder {
                    switch selectedTab {
                    case .review:
                        reviewContent
                    case .shared:
                        AllVideosTabView(folder: folder, videos: filterByTag(viewModel.sharedVideos), isLoading: viewModel.isLoading, isLoadingMore: viewModel.isLoadingMore, hasMoreVideos: viewModel.hasMoreVideos, errorMessage: viewModel.errorMessage, unreadVideoIDs: activityNotifService.unreadVideoIDs, onRefresh: {
                            await viewModel.loadVideos()
                        }, onLoadMore: {
                            await viewModel.loadMoreVideos()
                        }, onEditTags: { video in
                            editingVideoTags = video
                            editingTags = video.tags
                            editingDrillType = video.drillType
                            showingTagEditor = true
                        })
                    }
                } else {
                    // Games folder: flat list, filtered by gamesFilter
                    let sourceVideos = (gamesFilter == .needsReview)
                        ? viewModel.needsReviewVideos
                        : viewModel.allVideos
                    if gamesFilter == .needsReview && sourceVideos.isEmpty && !viewModel.isLoading {
                        EmptyFolderView(
                            icon: "checkmark.circle.fill",
                            title: "All Caught Up",
                            message: "No clips waiting for your review in this folder."
                        )
                    } else {
                        AllVideosTabView(folder: folder, videos: filterByTag(sourceVideos), isLoading: viewModel.isLoading, isLoadingMore: viewModel.isLoadingMore, hasMoreVideos: viewModel.hasMoreVideos, errorMessage: viewModel.errorMessage, unreadVideoIDs: activityNotifService.unreadVideoIDs, onRefresh: {
                            await viewModel.loadVideos()
                        }, onLoadMore: {
                            await viewModel.loadMoreVideos()
                        }, onEditTags: nil)
                    }
                }
            }
        }
    }

    // MARK: - Review (Lessons)

    @ViewBuilder
    private var reviewContent: some View {
        let clips = viewModel.reviewVideos
        if viewModel.isLoading && clips.isEmpty {
            VStack { Spacer(); ProgressView("Loading clips..."); Spacer() }
        } else if clips.isEmpty {
            EmptyFolderView(
                icon: "checkmark.circle",
                title: "All Caught Up",
                message: "No clips to review. Start a session to record clips for this athlete."
            )
        } else {
            VStack(spacing: 0) {
                if !isSharingAll {
                    HStack {
                        Text("\(clips.count) clip\(clips.count == 1 ? "" : "s") to review")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            shareAllReviewClips()
                        } label: {
                            Label("Share All", systemImage: "paperplane.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                } else {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        if let progress = shareProgress {
                            Text("Sharing clip \(progress.current) of \(progress.total)...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Sharing clips...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(clips) { clip in
                            Button {
                                reviewingClip = clip
                            } label: {
                                CoachVideoCard(video: clip)
                            }
                            .buttonStyle(PressableCardButtonStyle())
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await viewModel.loadVideos()
                }
            }
        }
    }

    private func shareAllReviewClips() {
        let clips = viewModel.reviewVideos
        guard !clips.isEmpty, let folderID = folder.id else { return }
        isSharingAll = true
        shareProgress = (current: 0, total: clips.count)

        Task {
            var sharedCount = 0
            for clip in clips {
                let videoID = clip.id
                do {
                    try await FirestoreManager.shared.publishPrivateVideo(
                        videoID: videoID,
                        sharedFolderID: folderID
                    )
                    sharedCount += 1
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "CoachFolderDetail.shareAll", showAlert: false)
                }
                shareProgress = (current: sharedCount, total: clips.count)
            }

            // No bundled client notification — per-clip server CFs (onVideoPublished
            // for coach-authored clips transitioning private→shared) write one
            // notification per clip to the athlete. More informative than a single
            // "N clips" summary and avoids client/server duplication.
            await viewModel.loadVideos()
            isSharingAll = false
            shareProgress = nil
            Haptics.success()
        }
    }

    @MainActor
    private func leaveFolder() async {
        guard let coachID = authManager.userID,
              let folderID = folder.id else { return }
        isLeaving = true
        do {
            try await SharedFolderManager.shared.leaveFolder(folderID: folderID, coachID: coachID)
            Haptics.success()
            dismiss()
        } catch {
            permissionError = "We couldn't remove you from this folder. Please try again."
            showingPermissionError = true
            ErrorHandlerService.shared.handle(error, context: "CoachFolderDetailView.leaveFolder", showAlert: false)
            isLeaving = false
        }
    }

    /// Verify folder access in the background — if revoked, show error overlay.
    @MainActor
    private func verifyPermissionsInBackground() async {
        guard let coachID = authManager.userID,
              let folderID = folder.id else { return }
        do {
            let updated = try await SharedFolderManager.shared.verifyFolderAccess(
                folderID: folderID,
                coachID: coachID
            )
            verifiedFolder = updated
            lastRefreshed = Date()
        } catch {
            permissionError = "Your access to this folder has been revoked. Contact the athlete for a new invitation."
            showingPermissionError = true
        }
    }

    @MainActor
    private func refreshPermissions() async {
        guard let coachID = authManager.userID,
              let folderID = folder.id else {
            return
        }

        isRefreshingPermissions = true
        Haptics.light()

        do {
            let updated = try await SharedFolderManager.shared.verifyFolderAccess(
                folderID: folderID,
                coachID: coachID
            )
            verifiedFolder = updated
            lastRefreshed = Date()
            Haptics.success()
        } catch {
            permissionError = "Failed to refresh permissions: \(error.localizedDescription)"
            showingPermissionError = true
            ErrorHandlerService.shared.handle(error, context: "CoachFolderDetailView.refreshPermissions", showAlert: false)
        }

        isRefreshingPermissions = false
    }

    private func quickRecord() {
        // If there's already an active session for this folder, resume recording
        if let active = CoachSessionManager.shared.activeSession {
            let folderID = folder.id ?? ""
            if active.folderIDs.values.contains(folderID) {
                showingQuickRecord = true
                return
            } else {
                showingActiveSessionAlert = true
                return
            }
        }
        guard let folderID = folder.id,
              let coachID = authManager.userID else { return }
        let coachName = authManager.userDisplayName ?? authManager.userEmail ?? "Coach"
        let athlete = (
            athleteID: folder.ownerAthleteID,
            athleteName: folder.ownerAthleteName ?? "Athlete",
            folderID: folderID
        )
        Task {
            do {
                let sessionID = try await CoachSessionManager.shared.scheduleSession(
                    coachID: coachID,
                    coachName: coachName,
                    athletes: [athlete],
                    scheduledDate: nil,
                    notes: nil,
                    authManager: authManager
                )
                try await CoachSessionManager.shared.startScheduledSession(sessionID: sessionID)
                Haptics.success()
                showingQuickRecord = true
            } catch {
                ErrorHandlerService.shared.handle(error, context: "CoachFolderDetail.quickRecord", showAlert: false)
            }
        }
    }

    private var canUpload: Bool {
        guard let coachID = authManager.userID,
              let verified = verifiedFolder else {
            return false
        }
        return verified.getPermissions(for: coachID)?.canUpload ?? false
    }

    private func refreshAvailableTags() {
        let visibleVideos: [CoachVideoItem]
        if isLessonsFolder {
            switch selectedTab {
            case .review: visibleVideos = viewModel.reviewVideos
            case .shared: visibleVideos = viewModel.sharedVideos
            }
        } else {
            visibleVideos = viewModel.allVideos
        }
        cachedAvailableTags = Array(Set(visibleVideos.flatMap(\.tags))).sorted()
    }

    /// Filters videos by the currently selected tag
    private func filterByTag(_ videos: [CoachVideoItem]) -> [CoachVideoItem] {
        guard let tag = selectedTagFilter else { return videos }
        return videos.filter { $0.tags.contains(tag) }
    }
}

// MARK: - Folder Sheets Modifier

private struct FolderSheetsModifier: ViewModifier {
    @Binding var showingUploadSheet: Bool
    @Binding var showingTagEditor: Bool
    @Binding var editingTags: [String]
    @Binding var editingDrillType: String?
    @Binding var tagEditorDidSave: Bool
    let verifiedFolder: SharedFolder?
    let editingVideoTags: CoachVideoItem?
    let viewModel: CoachFolderViewModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingUploadSheet) {
                if let verified = verifiedFolder {
                    CoachVideoUploadView(folder: verified)
                }
            }
            .sheet(isPresented: $showingTagEditor, onDismiss: {
                // Only save tags if the user explicitly tapped Done in the editor
                guard tagEditorDidSave, let video = editingVideoTags else {
                    tagEditorDidSave = false
                    return
                }
                tagEditorDidSave = false
                Task {
                    do {
                        try await FirestoreManager.shared.updateVideoTags(
                            videoID: video.id,
                            tags: editingTags,
                            drillType: editingDrillType
                        )
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "CoachFolderDetail.updateTags", showAlert: false)
                    }
                    await viewModel.loadVideos()
                }
            }) {
                VideoTagEditor(selectedTags: $editingTags, drillType: $editingDrillType, onSave: {
                    tagEditorDidSave = true
                })
            }
    }
}

// MARK: - Folder Dialogs Modifier

private struct FolderDialogsModifier: ViewModifier {
    @Binding var showingPermissionError: Bool
    @Binding var showingLeaveConfirmation: Bool
    let permissionError: String?
    let folderName: String
    let onLeave: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Access Error", isPresented: $showingPermissionError) {
                Button("OK") { }
            } message: {
                if let error = permissionError {
                    Text(error)
                }
            }
            .confirmationDialog("Leave \"\(folderName)\"?", isPresented: $showingLeaveConfirmation, titleVisibility: .visible) {
                Button("Leave Folder", role: .destructive) { onLeave() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll lose access to all videos in this folder. The athlete can re-invite you later.")
            }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CoachFolderDetailView(
            folder: SharedFolder(
                id: "preview",
                name: "Coach Smith Folder",
                ownerAthleteID: "athlete123",
                ownerAthleteName: "Test Athlete",
                sharedWithCoachIDs: ["coach456"],
                permissions: [:],
                createdAt: Date(),
                updatedAt: Date(),
                videoCount: 12
            )
        )
    }
    .environmentObject(ComprehensiveAuthManager())
    .environment(CoachNavigationCoordinator())
}
