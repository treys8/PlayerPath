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
    @StateObject private var viewModel: CoachFolderViewModel
    @State private var selectedTab: FolderTab = .games
    @State private var showingUploadSheet = false
    
    init(folder: SharedFolder) {
        self.folder = folder
        _viewModel = StateObject(wrappedValue: CoachFolderViewModel(folder: folder))
    }
    
    enum FolderTab: String, CaseIterable {
        case games = "Games"
        case practices = "Practices"
        case all = "All Videos"
        
        var icon: String {
            switch self {
            case .games: return "figure.baseball"
            case .practices: return "figure.run"
            case .all: return "video.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Folder info header
            FolderInfoHeader(folder: folder, videoCount: viewModel.videos.count)
            
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
                    GamesTabView(folder: folder, videos: viewModel.gameVideos)
                case .practices:
                    PracticesTabView(folder: folder, videos: viewModel.practiceVideos)
                case .all:
                    AllVideosTabView(folder: folder, videos: viewModel.videos)
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if canUpload {
                    Button {
                        showingUploadSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .sheet(isPresented: $showingUploadSheet) {
            CoachVideoUploadView(folder: folder, selectedTab: selectedTab)
        }
        .task {
            await viewModel.loadVideos()
        }
    }
    
    private var canUpload: Bool {
        guard let coachID = authManager.userID else { return false }
        return folder.getPermissions(for: coachID)?.canUpload ?? false
    }
}

// MARK: - Folder Info Header

struct FolderInfoHeader: View {
    let folder: SharedFolder
    let videoCount: Int
    
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
    
    var body: some View {
        Group {
            if videos.isEmpty {
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
    
    var body: some View {
        Group {
            if videos.isEmpty {
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
    
    var body: some View {
        Group {
            if videos.isEmpty {
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
            }
        }
    }
}

// MARK: - Video Row Component

struct CoachVideoRow: View {
    let video: CoachVideoItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail placeholder
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(width: 120)
                    .cornerRadius(8)
                
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            
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
                
                if let context = video.contextLabel {
                    Text(context)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
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
