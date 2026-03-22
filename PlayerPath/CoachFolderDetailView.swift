//
//  CoachFolderDetailView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Detailed view of a shared folder with Games and Practices organization
//

import SwiftUI
import Combine
import FirebaseAuth

/// Shows the contents of a shared folder with Games and Practices sections
struct CoachFolderDetailView: View {
    let folder: SharedFolder

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CoachFolderViewModel
    @State private var selectedTab: FolderTab = .games
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
    @ObservedObject private var archiveManager = CoachFolderArchiveManager.shared

    init(folder: SharedFolder) {
        self.folder = folder
        _viewModel = StateObject(wrappedValue: CoachFolderViewModel(folder: folder))
        _verifiedFolder = State(initialValue: folder)
    }
    
    enum FolderTab: String, CaseIterable {
        case games = "Games"
        case instruction = "Instruction"
        case all = "All Videos"
        case myRecordings = "My Recordings"

        var icon: String {
            switch self {
            case .games: return "figure.baseball"
            case .instruction: return "figure.run"
            case .all: return "video"
            case .myRecordings: return "video.badge.plus"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Folder info header
            FolderInfoHeader(folder: folder, videoCount: viewModel.videos.count, lastRefreshed: lastRefreshed)
            
            // Tab picker
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
            }

            // Tag filter bar
            if !availableTags.isEmpty && selectedTab != .myRecordings {
                VideoTagFilterBar(
                    tags: availableTags,
                    selectedTag: $selectedTagFilter
                )
            }

            // Content based on selected tab
            Group {
                switch selectedTab {
                case .games:
                    GamesTabView(folder: folder, videos: filterByTag(viewModel.cachedGameVideos), isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage) {
                        await viewModel.loadVideos()
                    }
                case .instruction:
                    InstructionTabView(folder: folder, videos: filterByTag(viewModel.cachedInstructionVideos), isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage) {
                        await viewModel.loadVideos()
                    }
                case .all:
                    AllVideosTabView(folder: folder, videos: filterByTag(viewModel.videos), isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage, onRefresh: {
                        await viewModel.loadVideos()
                    }, onEditTags: { video in
                        editingVideoTags = video
                        editingTags = video.tags
                        editingDrillType = video.drillType
                        showingTagEditor = true
                    })
                case .myRecordings:
                    CoachPrivateVideosTab(folder: folder, canUpload: canUpload)
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    Task {
                        await refreshPermissions()
                    }
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
        }
        .sheet(isPresented: $showingUploadSheet) {
            if let verified = verifiedFolder {
                CoachVideoUploadView(folder: verified, selectedTab: selectedTab)
            }
        }
        .sheet(isPresented: $showingTagEditor) {
            VideoTagEditor(selectedTags: $editingTags, drillType: $editingDrillType)
                .onDisappear {
                    guard let video = editingVideoTags else { return }
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
                }
        }
        .task {
            if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < 60 { return }
            // Load videos immediately while verifying permissions in parallel
            async let videosTask: () = viewModel.loadVideos()
            async let permissionTask: () = verifyPermissionsInBackground()
            _ = await (videosTask, permissionTask)
            lastFetchDate = Date()
        }
        .alert("Access Error", isPresented: $showingPermissionError) {
            Button("OK") { }
        } message: {
            if let error = permissionError {
                Text(error)
            }
        }
        .confirmationDialog("Leave \"\(folder.name)\"?", isPresented: $showingLeaveConfirmation, titleVisibility: .visible) {
            Button("Leave Folder", role: .destructive) {
                Task { await leaveFolder() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll lose access to all videos in this folder. The athlete can re-invite you later.")
        }
        .disabled(isLeaving)
        .overlay {
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

    /// All unique tags across videos in this folder
    /// Tags available for filtering, scoped to the active tab's videos
    private var availableTags: [String] {
        let visibleVideos: [CoachVideoItem]
        switch selectedTab {
        case .games: visibleVideos = viewModel.cachedGameVideos
        case .instruction: visibleVideos = viewModel.cachedInstructionVideos
        case .all: visibleVideos = viewModel.videos
        case .myRecordings: visibleVideos = []
        }
        return Array(Set(visibleVideos.flatMap(\.tags))).sorted()
    }

    /// Filters videos by the currently selected tag
    private func filterByTag(_ videos: [CoachVideoItem]) -> [CoachVideoItem] {
        guard let tag = selectedTagFilter else { return videos }
        return videos.filter { $0.tags.contains(tag) }
    }
}

// MARK: - Folder Info Header

struct FolderInfoHeader: View {
    let folder: SharedFolder
    let videoCount: Int
    let lastRefreshed: Date?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.title)
                    .foregroundColor(.brandNavy)

                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.name)
                        .font(.headline)

                    Text("\(videoCount) video\(videoCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let refreshed = lastRefreshed {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("Updated \(refreshed.formatted(.relative(presentation: .named)))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Games Tab View

struct GamesTabView: View {
    let folder: SharedFolder
    let videos: [CoachVideoItem]
    var isLoading: Bool = false
    var errorMessage: String? = nil
    let onRefresh: () async -> Void

    @State private var cachedGameGroups: [GameGroup] = []

    var body: some View {
        Group {
            if isLoading && videos.isEmpty {
                ProgressView("Loading game videos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, videos.isEmpty {
                EmptyFolderView(
                    icon: "exclamationmark.triangle",
                    title: "Failed to Load",
                    message: error
                )
            } else if videos.isEmpty {
                EmptyFolderView(
                    icon: "figure.baseball",
                    title: "No Game Videos",
                    message: "Game videos will appear here once they're uploaded."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(cachedGameGroups, id: \.opponent) { group in
                            GameGroupView(folder: folder, gameGroup: group)
                        }
                    }
                    .padding()
                }
                .refreshable { await onRefresh() }
            }
        }
        .onAppear { updateGroupedVideos() }
        .onChange(of: videos.count) { updateGroupedVideos() }
    }

    private func updateGroupedVideos() {
        let grouped = Dictionary(grouping: videos) { video -> String in
            video.gameOpponent ?? "Unknown Game"
        }

        cachedGameGroups = grouped.map { opponent, videos in
            GameGroup(
                opponent: opponent,
                date: videos.first?.createdAt ?? Date(),
                videos: videos.sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
            )
        }.sorted { $0.date > $1.date }
    }
}

struct GameGroup {
    let opponent: String
    let date: Date
    let videos: [CoachVideoItem]
}

struct GameGroupView: View {
    let folder: SharedFolder
    let gameGroup: GameGroup
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(spacing: 8) {
            // Game header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gameGroup.opponent)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(gameGroup.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Text("\(gameGroup.videos.count) video\(gameGroup.videos.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            // Videos list
            if isExpanded {
                ForEach(gameGroup.videos) { video in
                    NavigationLink(destination: CoachVideoPlayerView(folder: folder, video: video)) {
                        CoachVideoRow(video: video)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Practices Tab View

struct InstructionTabView: View {
    let folder: SharedFolder
    let videos: [CoachVideoItem]
    var isLoading: Bool = false
    var errorMessage: String? = nil
    let onRefresh: () async -> Void

    @State private var cachedPracticeGroups: [PracticeGroup] = []

    var body: some View {
        Group {
            if isLoading && videos.isEmpty {
                ProgressView("Loading practice videos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, videos.isEmpty {
                EmptyFolderView(
                    icon: "exclamationmark.triangle",
                    title: "Failed to Load",
                    message: error
                )
            } else if videos.isEmpty {
                EmptyFolderView(
                    icon: "figure.run",
                    title: "No Practice Videos",
                    message: "Practice videos will appear here once they're uploaded."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(cachedPracticeGroups, id: \.date) { group in
                            PracticeGroupView(folder: folder, practiceGroup: group)
                        }
                    }
                    .padding()
                }
                .refreshable { await onRefresh() }
            }
        }
        .onAppear { updateGroupedVideos() }
        .onChange(of: videos.count) { updateGroupedVideos() }
    }

    private func updateGroupedVideos() {
        let grouped = Dictionary(grouping: videos) { video -> Date in
            let calendar = Calendar.current
            return calendar.startOfDay(for: video.practiceDate ?? video.createdAt ?? Date())
        }

        cachedPracticeGroups = grouped.map { date, videos in
            PracticeGroup(
                date: date,
                videos: videos.sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
            )
        }.sorted { $0.date > $1.date }
    }
}

struct PracticeGroup {
    let date: Date
    let videos: [CoachVideoItem]
}

struct PracticeGroupView: View {
    let folder: SharedFolder
    let practiceGroup: PracticeGroup
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(spacing: 8) {
            // Practice header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Instruction")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(practiceGroup.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Text("\(practiceGroup.videos.count) video\(practiceGroup.videos.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            // Videos list
            if isExpanded {
                ForEach(practiceGroup.videos) { video in
                    NavigationLink(destination: CoachVideoPlayerView(folder: folder, video: video)) {
                        CoachVideoRow(video: video)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - All Videos Tab View

struct AllVideosTabView: View {
    let folder: SharedFolder
    let videos: [CoachVideoItem]
    var isLoading: Bool = false
    var errorMessage: String? = nil
    let onRefresh: () async -> Void
    var onEditTags: ((CoachVideoItem) -> Void)?

    var body: some View {
        Group {
            if isLoading && videos.isEmpty {
                ProgressView("Loading videos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, videos.isEmpty {
                EmptyFolderView(
                    icon: "exclamationmark.triangle",
                    title: "Failed to Load",
                    message: error
                )
            } else if videos.isEmpty {
                EmptyFolderView(
                    icon: "video.slash",
                    title: "No Videos Yet",
                    message: "Videos will appear here once you or the athlete uploads them."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(videos) { video in
                            NavigationLink(destination: CoachVideoPlayerView(folder: folder, video: video)) {
                                CoachVideoRow(video: video, onEditTags: onEditTags != nil ? { onEditTags?(video) } : nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .refreshable { await onRefresh() }
            }
        }
    }
}

// MARK: - Video Row Component

struct CoachVideoRow: View {
    let video: CoachVideoItem
    var onEditTags: (() -> Void)?

    private var thumbnailPlaceholder: some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.3))
            Image(systemName: "play.circle.fill")
                .font(.title)
                .foregroundColor(.white)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                if let urlString = video.thumbnailURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                        case .failure, .empty:
                            thumbnailPlaceholder
                        @unknown default:
                            thumbnailPlaceholder
                        }
                    }
                } else {
                    thumbnailPlaceholder
                }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(video.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    Label(video.uploadedByName, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let date = video.createdAt {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 8) {
                    if let context = video.contextLabel {
                        Text(context)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.brandNavy.opacity(0.1))
                            .foregroundColor(.brandNavy)
                            .cornerRadius(4)
                    }

                    if let count = video.annotationCount, count > 0 {
                        Label("\(count)", systemImage: "bubble.left.fill")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }

                // Tags
                if !video.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(video.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                        if video.tags.count > 3 {
                            Text("+\(video.tags.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
        .contextMenu {
            if let onEditTags {
                Button {
                    onEditTags()
                } label: {
                    Label("Edit Tags", systemImage: "tag")
                }
            }
        }
    }
}

// MARK: - Empty State View

struct EmptyFolderView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text(title)
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - View Model

@MainActor
class CoachFolderViewModel: ObservableObject {
    let folder: SharedFolder
    
    @Published var videos: [CoachVideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init(folder: SharedFolder) {
        self.folder = folder
    }
    
    /// Cached filtered arrays — updated whenever `videos` changes
    @Published var cachedGameVideos: [CoachVideoItem] = []
    @Published var cachedInstructionVideos: [CoachVideoItem] = []

    private func updateFilteredVideos() {
        cachedGameVideos = videos.filter { $0.videoType == "game" || $0.gameOpponent != nil }
        cachedInstructionVideos = videos.filter { $0.videoType == "instruction" || $0.videoType == "practice" || ($0.practiceDate != nil && $0.gameOpponent == nil) }
    }
    
    func loadVideos() async {
        isLoading = true
        defer { isLoading = false }

        guard let folderID = folder.id else {
            errorMessage = "Invalid folder"
            return
        }

        do {
            let firestoreVideos = try await FirestoreManager.shared.fetchVideos(forSharedFolder: folderID)

            // Convert to CoachVideoItem, filtering out other coaches' private videos
            let currentUserID = Auth.auth().currentUser?.uid
            videos = firestoreVideos
                .filter { video in
                    // Show: shared videos, own private videos, legacy videos (no visibility)
                    video.visibility != "private" || video.uploadedBy == currentUserID
                }
                .map { CoachVideoItem(from: $0) }
                .sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
            updateFilteredVideos()

            // Pre-fetch signed URLs in background so tapping a video
            // doesn't block on a Cloud Function round-trip (200-800ms).
            // The 24-hour expiry makes this safe to do eagerly.
            let fileNames = videos.map(\.fileName)
            if !fileNames.isEmpty {
                Task {
                    do {
                        _ = try await SecureURLManager.shared.getBatchSecureVideoURLs(
                            fileNames: fileNames,
                            folderID: folderID
                        )
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "CoachFolderDetail.prefetchURLs", showAlert: false)
                    }
                }
            }

        } catch {
            errorMessage = "Failed to load videos: \(error.localizedDescription)"
        }
    }
}

// MARK: - Video Item Model

struct CoachVideoItem: Identifiable {
    let id: String
    let fileName: String
    let firebaseStorageURL: String
    let thumbnailURL: String?
    let uploadedBy: String
    let uploadedByName: String
    let sharedFolderID: String
    let createdAt: Date?
    let fileSize: Int64?
    let duration: Double?
    let isHighlight: Bool
    
    // Context info
    let videoType: String?
    let gameOpponent: String?
    let gameDate: Date?
    let practiceDate: Date?
    let notes: String?
    let annotationCount: Int?
    let tags: [String]
    let drillType: String?
    var visibility: String? = nil

    var contextLabel: String? {
        if let opponent = gameOpponent {
            return "Game vs \(opponent)"
        } else if let _ = practiceDate {
            return "Instruction"
        }
        return nil
    }
    
    init(from metadata: FirestoreVideoMetadata) {
        self.id = metadata.id ?? UUID().uuidString
        self.fileName = metadata.fileName
        self.firebaseStorageURL = metadata.firebaseStorageURL
        self.thumbnailURL = metadata.thumbnail?.standardURL
        self.uploadedBy = metadata.uploadedBy
        self.uploadedByName = metadata.uploadedByName
        self.sharedFolderID = metadata.sharedFolderID
        self.createdAt = metadata.createdAt
        self.fileSize = metadata.fileSize
        self.duration = metadata.duration
        self.isHighlight = metadata.isHighlight ?? false
        
        // Extract context info from metadata
        self.videoType = metadata.videoType
        self.gameOpponent = metadata.gameOpponent
        self.gameDate = metadata.gameDate
        self.practiceDate = metadata.practiceDate
        self.notes = metadata.notes
        self.annotationCount = metadata.annotationCount
        self.tags = metadata.tags ?? []
        self.drillType = metadata.drillType
        self.visibility = metadata.visibility
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
}
