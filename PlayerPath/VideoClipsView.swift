//
//  VideoClipsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 11/17/25.
//

import SwiftUI
import SwiftData
import AVKit

struct VideoClipsView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @State private var showingRecorder = false
    @State private var showingUploadPicker = false
    @State private var selectedVideo: VideoClip?
    @State private var showingPlayer = false
    @State private var searchText = ""
    @State private var liveGameContext: Game?
    @State private var refreshTrigger = UUID()

    private var filteredVideos: [VideoClip] {
        // Force refresh by accessing refreshTrigger
        _ = refreshTrigger
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return (athlete.videoClips ?? []).sorted { (lhs: VideoClip, rhs: VideoClip) in
                switch (lhs.createdAt, rhs.createdAt) {
                case let (l?, r?):
                    return l > r
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return false
                }
            }
        }
        
        return (athlete.videoClips ?? []).filter { video in
            video.fileName.lowercased().contains(query) ||
            (video.playResult?.type.displayName.lowercased().contains(query) ?? false)
        }.sorted { (lhs: VideoClip, rhs: VideoClip) in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?):
                return l > r
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                return false
            }
        }
    }
    
    var body: some View {
        Group {
            if athlete.videoClips?.isEmpty ?? true {
                emptyStateView
            } else {
                videoListView
            }
        }
        .navigationTitle("Videos")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search videos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Haptics.light()
                        showingRecorder = true
                    } label: {
                        Label("Record Video", systemImage: "video.badge.plus")
                    }
                    
                    Button {
                        Haptics.light()
                        showingUploadPicker = true
                    } label: {
                        Label("Upload from Library", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add video")
            }
        }
        .sheet(isPresented: $showingRecorder) {
            VideoRecorderView_Refactored(athlete: athlete, game: liveGameContext)
        }
        .sheet(isPresented: $showingUploadPicker) {
            // TODO: Implement video upload picker
            Text("Video upload coming soon")
        }
        .sheet(item: $selectedVideo) { video in
            VideoPlayer(player: AVPlayer(url: URL(fileURLWithPath: video.filePath)))
                .ignoresSafeArea()
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentVideoRecorder)) { notification in
            liveGameContext = notification.object as? Game
            showingRecorder = true
            Haptics.light()
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentFullscreenVideo)) { notification in
            if let video = notification.object as? VideoClip {
                selectedVideo = video
                Haptics.light()
            }
        }
        .onAppear {
            // Tell MainTabView that Videos manages its own controls
            NotificationCenter.default.post(name: .videosManageOwnControls, object: true)
        }
        .onDisappear {
            // Reset when leaving Videos tab
            NotificationCenter.default.post(name: .videosManageOwnControls, object: false)
            liveGameContext = nil
        }
        .onChange(of: athlete.videoClips?.count) { _, _ in
            refreshTrigger = UUID()
        }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            systemImage: "video.slash",
            title: "No Videos Yet",
            message: "Record your first video to build your highlight reel",
            actionTitle: "Record Video",
            action: {
                Haptics.light()
                showingRecorder = true
            }
        )
    }
    
    private var videoListView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12, alignment: .top)
                ],
                spacing: 12
            ) {
                ForEach(filteredVideos) { video in
                    VideoClipCard(video: video) {
                        selectedVideo = video
                        Haptics.light()
                    }
                }
            }
            .padding()
        }
    }
}

struct VideoClipCard: View {
    let video: VideoClip
    let action: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                // Thumbnail with aspect ratio
                GeometryReader { geometry in
                    ZStack {
                        if let image = thumbnailImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(LinearGradient(
                                    colors: [.gray.opacity(0.3), .gray.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                            
                            ProgressView()
                        }
                        
                        // Play button overlay
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4)
                        
                        // Highlight star badge in corner
                        if video.isHighlight {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                        .font(.caption)
                                        .padding(6)
                                        .background(Circle().fill(.black.opacity(0.6)))
                                }
                                Spacer()
                            }
                            .padding(8)
                        }
                    }
                }
                .aspectRatio(16/9, contentMode: .fit) // Landscape video aspect ratio
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                
                // Info section - more compact
                VStack(alignment: .leading, spacing: 6) {
                    if let result = video.playResult {
                        Text(result.type.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    } else {
                        Text(video.fileName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                    
                    if let created = video.createdAt {
                        Text(created, format: .dateTime.month().day())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if let game = video.game {
                        HStack(spacing: 3) {
                            Image(systemName: "baseball.fill")
                                .font(.system(size: 8))
                            Text(game.opponent)
                                .lineLimit(1)
                        }
                        .font(.caption2)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Haptics.light()
                action()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            
            Button {
                Haptics.light()
                video.isHighlight.toggle()
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to toggle highlight: \(error)")
                }
            } label: {
                Label(
                    video.isHighlight ? "Remove from Highlights" : "Add to Highlights",
                    systemImage: video.isHighlight ? "star.slash" : "star.fill"
                )
            }
            
            if FileManager.default.fileExists(atPath: video.filePath) {
                ShareLink(item: URL(fileURLWithPath: video.filePath)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                deleteVideo(video)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        guard thumbnailImage == nil else { return }
        
        if let path = video.thumbnailPath {
            do {
                let image = try await ThumbnailCache.shared.loadThumbnail(at: path)
                await MainActor.run {
                    thumbnailImage = image
                }
            } catch {
                // Generate thumbnail if it doesn't exist
                await generateThumbnail()
            }
        } else {
            await generateThumbnail()
        }
    }
    
    private func generateThumbnail() async {
        let url = URL(fileURLWithPath: video.filePath)
        guard FileManager.default.fileExists(atPath: video.filePath) else { return }
        
        let result = await VideoFileManager.generateThumbnail(from: url)
        
        switch result {
        case .success(let path):
            await MainActor.run {
                video.thumbnailPath = path
                // Load the generated thumbnail
                Task {
                    if let image = try? await ThumbnailCache.shared.loadThumbnail(at: path) {
                        thumbnailImage = image
                    }
                }
                try? modelContext.save()
            }
        case .failure(let error):
            print("Failed to generate thumbnail: \(error)")
        }
    }
    
    private func deleteVideo(_ video: VideoClip) {
        Haptics.medium()
        
        // Delete file
        if FileManager.default.fileExists(atPath: video.filePath) {
            try? FileManager.default.removeItem(atPath: video.filePath)
        }
        
        // Delete thumbnail
        if let thumbPath = video.thumbnailPath {
            try? FileManager.default.removeItem(atPath: thumbPath)
        }
        
        // Delete from database
        modelContext.delete(video)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete video: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        VideoClipsView(athlete: Athlete(name: "Test Player"))
    }
    .modelContainer(for: [Athlete.self, VideoClip.self])
}
