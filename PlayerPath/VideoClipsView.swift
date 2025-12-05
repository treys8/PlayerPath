//
//  VideoClipsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 11/17/25.
//

import SwiftUI
import SwiftData
import AVKit
import PhotosUI

struct VideoClipsView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @State private var showingRecorder = false
    @State private var showingUploadPicker = false
    @State private var selectedVideo: VideoClip?
    @State private var searchText = ""
    @State private var liveGameContext: Game?
    @State private var refreshTrigger = UUID()
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isImporting = false
    @State private var videoToDelete: VideoClip?
    @State private var showingDeleteConfirmation = false

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
            VideoPicker(athlete: athlete, onError: { error in
                errorMessage = error
                showingError = true
            }, onImportStart: {
                isImporting = true
            }, onImportComplete: {
                isImporting = false
                refreshTrigger = UUID()
            })
        }
        .sheet(item: $selectedVideo) { video in
            if FileManager.default.fileExists(atPath: video.filePath) {
                VideoPlayer(player: AVPlayer(url: URL(fileURLWithPath: video.filePath)))
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    Text("Video File Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("The video file may have been deleted or moved.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
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
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .confirmationDialog("Delete Video", isPresented: $showingDeleteConfirmation, presenting: videoToDelete) { video in
            Button("Delete", role: .destructive) {
                performDelete(video)
            }
            Button("Cancel", role: .cancel) { }
        } message: { video in
            Text("Are you sure you want to delete this video? This action cannot be undone.")
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Importing Video...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 20)
                }
            }
        }
    }

    private func performDelete(_ video: VideoClip) {
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
            errorMessage = "Failed to delete video: \(error.localizedDescription)"
            showingError = true
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
                    VideoClipCard(video: video, onPlay: {
                        selectedVideo = video
                        Haptics.light()
                    }, onDelete: {
                        videoToDelete = video
                        showingDeleteConfirmation = true
                    })
                }
            }
            .padding()
        }
    }
}

struct VideoClipCard: View {
    let video: VideoClip
    let onPlay: () -> Void
    let onDelete: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var thumbnailImage: UIImage?
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        Button(action: onPlay) {
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
                onPlay()
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                Haptics.light()
                video.isHighlight.toggle()
                do {
                    try modelContext.save()
                } catch {
                    errorMessage = "Failed to toggle highlight: \(error.localizedDescription)"
                    showingError = true
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
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
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
                do {
                    try modelContext.save()
                } catch {
                    // Silent failure for thumbnail save - not critical
                }
            }
        case .failure:
            // Silent failure for thumbnail generation - will show placeholder
            return
        }
    }
}

#Preview {
    NavigationStack {
        VideoClipsView(athlete: Athlete(name: "Test Player"))
    }
    .modelContainer(for: [Athlete.self, VideoClip.self])
}
