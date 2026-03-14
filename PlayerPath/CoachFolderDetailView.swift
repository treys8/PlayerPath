//
//  CoachFolderDetailView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Detailed view of a shared folder with Games and Practices organization
//

import SwiftUI
import Combine

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
    @ObservedObject private var archiveManager = CoachFolderArchiveManager.shared

    init(folder: SharedFolder) {
        self.folder = folder
        _viewModel = StateObject(wrappedValue: CoachFolderViewModel(folder: folder))
        _verifiedFolder = State(initialValue: folder)
    }
    
    enum FolderTab: String, CaseIterable {
        case games = "Games"
        case practices = "Practices"
        case all = "All Videos"
        
        var icon: String {
            switch self {
            case .games: return "figure.baseball"
            case .practices: return "figure.run"
            case .all: return "video"
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
            
            // Content based on selected tab
            Group {
                switch selectedTab {
                case .games:
                    GamesTabView(folder: folder, videos: viewModel.gameVideos, isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage) {
                        await viewModel.loadVideos()
                    }
                case .practices:
                    PracticesTabView(folder: folder, videos: viewModel.practiceVideos, isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage) {
                        await viewModel.loadVideos()
                    }
                case .all:
                    AllVideosTabView(folder: folder, videos: viewModel.videos, isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage) {
                        await viewModel.loadVideos()
                    }
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
                            .foregroundColor(.blue)
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
        .task {
            await loadWithPermissionCheck()
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
            Haptics.error()
            isLeaving = false
        }
    }

    @MainActor
    private func loadWithPermissionCheck() async {
        guard let coachID = authManager.userID,
              let folderID = folder.id else {
            return
        }

        // Verify permissions from Firestore
        do {
            let updated = try await SharedFolderManager.shared.verifyFolderAccess(
                folderID: folderID,
                coachID: coachID
            )
            verifiedFolder = updated
            lastRefreshed = Date()
            print("✅ Verified permissions for folder: \(folder.name)")
        } catch {
            // Handle permission errors
            permissionError = error.localizedDescription
            showingPermissionError = true
            print("❌ Permission verification failed: \(error)")
            return
        }

        // Load videos after verification
        await viewModel.loadVideos()
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
            print("✅ Refreshed permissions for folder: \(folder.name)")
        } catch {
            permissionError = "Failed to refresh permissions: \(error.localizedDescription)"
            showingPermissionError = true
            Haptics.error()
            print("❌ Permission refresh failed: \(error)")
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
                    .foregroundColor(.blue)

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
                        ForEach(gameGroups, id: \.opponent) { group in
                            GameGroupView(folder: folder, gameGroup: group)
                        }
                    }
                    .padding()
                }
                .refreshable { await onRefresh() }
            }
        }
    }
    
    // Group videos by game opponent
    private var gameGroups: [GameGroup] {
        let grouped = Dictionary(grouping: videos) { video -> String in
            video.gameOpponent ?? "Unknown Game"
        }
        
        return grouped.map { opponent, videos in
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

struct PracticesTabView: View {
    let folder: SharedFolder
    let videos: [CoachVideoItem]
    var isLoading: Bool = false
    var errorMessage: String? = nil
    let onRefresh: () async -> Void

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
                        ForEach(practiceGroups, id: \.date) { group in
                            PracticeGroupView(folder: folder, practiceGroup: group)
                        }
                    }
                    .padding()
                }
                .refreshable { await onRefresh() }
            }
        }
    }
    
    // Group videos by practice date
    private var practiceGroups: [PracticeGroup] {
        let grouped = Dictionary(grouping: videos) { video -> Date in
            // Group by day (strip time component)
            let calendar = Calendar.current
            return calendar.startOfDay(for: video.practiceDate ?? video.createdAt ?? Date())
        }
        
        return grouped.map { date, videos in
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
                        Text("Practice")
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
                                CoachVideoRow(video: video)
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
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
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
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
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
    
    /// Videos marked as game videos (has gameOpponent)
    var gameVideos: [CoachVideoItem] {
        videos.filter { $0.videoType == "game" || $0.gameOpponent != nil }
    }
    
    /// Videos marked as practice videos (has practiceDate but no gameOpponent)
    var practiceVideos: [CoachVideoItem] {
        videos.filter { $0.videoType == "practice" || ($0.practiceDate != nil && $0.gameOpponent == nil) }
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
            
            // Convert to CoachVideoItem
            videos = firestoreVideos.map { CoachVideoItem(from: $0) }
                .sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
            
        } catch {
            errorMessage = "Failed to load videos: \(error.localizedDescription)"
            print("❌ Failed to load videos: \(error)")
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
    
    var contextLabel: String? {
        if let opponent = gameOpponent {
            return "Game vs \(opponent)"
        } else if let _ = practiceDate {
            return "Practice"
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
