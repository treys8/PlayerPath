//
//  CoachFolderDetailView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Detailed view of a shared folder with From Athlete / Needs Review / From Me tabs
//

import SwiftUI

/// Shows the contents of a shared folder with From Athlete / Needs Review / From Me tabs
struct CoachFolderDetailView: View {
    let folder: SharedFolder

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachNavigationCoordinator.self) private var coordinator
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
    private var archiveManager: CoachFolderArchiveManager { .shared }

    init(folder: SharedFolder, initialTab: FolderTab = .fromAthlete) {
        self.folder = folder
        _viewModel = State(initialValue: CoachFolderViewModel(folder: folder))
        _verifiedFolder = State(initialValue: folder)
        _selectedTab = State(initialValue: initialTab)
    }

    enum FolderTab: String, CaseIterable {
        case fromAthlete = "From Athlete"
        case needsReview = "Review"
        case fromMe = "From Me"

        var icon: String {
            switch self {
            case .fromAthlete: return "figure.baseball"
            case .needsReview: return "exclamationmark.circle"
            case .fromMe: return "arrow.up.circle"
            }
        }
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
            .sheet(item: $reviewingClip) { clip in
                ClipReviewSheet(
                    video: clip,
                    folder: folder,
                    onShared: { Task { await viewModel.loadVideos() } },
                    onDiscarded: { Task { await viewModel.loadVideos() } }
                )
            }
            .task { await initialLoad() }
            .onChange(of: viewModel.cachedFromAthleteVideos) { _, _ in refreshAvailableTags() }
            .onChange(of: viewModel.cachedFromMeVideos) { _, _ in refreshAvailableTags() }
            .onChange(of: viewModel.cachedNeedsReviewVideos) { _, _ in refreshAvailableTags() }
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
            if canUpload {
                Button {
                    showingUploadSheet = true
                } label: {
                    Label("Upload Video", systemImage: "plus.circle")
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

        if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < 60 { return }
        async let videosTask: () = viewModel.loadVideos()
        async let permissionTask: () = verifyPermissionsInBackground()
        _ = await (videosTask, permissionTask)
        lastFetchDate = Date()
    }

    // MARK: - Folder Content

    private var folderContent: some View {
        VStack(spacing: 0) {
            FolderInfoHeader(folder: folder, videoCount: viewModel.videos.count, lastRefreshed: lastRefreshed)

            Picker("View", selection: $selectedTab) {
                ForEach(FolderTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: selectedTab) { _, _ in
                selectedTagFilter = nil
                refreshAvailableTags()
            }

            if !cachedAvailableTags.isEmpty {
                VideoTagFilterBar(
                    tags: cachedAvailableTags,
                    selectedTag: $selectedTagFilter
                )
            }

            Group {
                switch selectedTab {
                case .fromAthlete:
                    AllVideosTabView(folder: folder, videos: filterByTag(viewModel.cachedFromAthleteVideos), isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage, onRefresh: {
                        await viewModel.loadVideos()
                    }, onEditTags: nil)
                case .needsReview:
                    needsReviewContent
                case .fromMe:
                    AllVideosTabView(folder: folder, videos: filterByTag(viewModel.cachedFromMeVideos), isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage, onRefresh: {
                        await viewModel.loadVideos()
                    }, onEditTags: { video in
                        editingVideoTags = video
                        editingTags = video.tags
                        editingDrillType = video.drillType
                        showingTagEditor = true
                    })
                }
            }
        }
    }

    // MARK: - Needs Review

    @ViewBuilder
    private var needsReviewContent: some View {
        let clips = viewModel.cachedNeedsReviewVideos
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
                        Text("Sharing clips...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(clips) { clip in
                            Button {
                                reviewingClip = clip
                            } label: {
                                CoachVideoRow(video: clip)
                            }
                            .buttonStyle(.plain)
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
        let clips = viewModel.cachedNeedsReviewVideos
        guard !clips.isEmpty, let folderID = folder.id else { return }
        isSharingAll = true

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
            }

            // Notify athlete once (not per-clip)
            if sharedCount > 0, let coachID = authManager.userID {
                let coachName = authManager.userDisplayName ?? "Coach"
                await ActivityNotificationService.shared.postNewVideoNotification(
                    folderID: folderID,
                    folderName: folder.name,
                    uploaderID: coachID,
                    uploaderName: coachName,
                    coachIDs: [folder.ownerAthleteID],
                    videoFileName: "\(sharedCount) clip\(sharedCount == 1 ? "" : "s")"
                )
            }

            await viewModel.loadVideos()
            isSharingAll = false
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
            permissionError = "Failed to leave folder: \(error.localizedDescription)"
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
            permissionError = error.localizedDescription
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

    private var canUpload: Bool {
        guard let coachID = authManager.userID,
              let verified = verifiedFolder else {
            return false
        }
        return verified.getPermissions(for: coachID)?.canUpload ?? false
    }

    private func refreshAvailableTags() {
        let visibleVideos: [CoachVideoItem]
        switch selectedTab {
        case .fromAthlete: visibleVideos = viewModel.cachedFromAthleteVideos
        case .needsReview: visibleVideos = viewModel.cachedNeedsReviewVideos
        case .fromMe: visibleVideos = viewModel.cachedFromMeVideos
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
