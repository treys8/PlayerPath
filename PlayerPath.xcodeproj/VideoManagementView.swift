//
//  VideoManagementView.swift
//  PlayerPath
//
//  Created by Assistant on 10/30/25.
//

import SwiftUI
import PhotosUI
import AVKit

struct VideoManagementView: View {
    @State private var videoManager = UnifiedVideoManager.shared
    @State private var selectedVideos: Set<String> = []
    @State private var showingPhotoPicker = false
    @State private var showingVideoPlayer: VideoRecord?
    @State private var showingBatchActions = false
    @State private var viewMode: ViewMode = .grid
    
    enum ViewMode: CaseIterable {
        case grid, list
        
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search and Filter Bar
                searchAndFilterBar
                
                // Storage Info Banner
                if videoManager.storageInfo.syncPending > 0 {
                    syncStatusBanner
                }
                
                // Video Grid/List
                videoContent
            }
            .navigationTitle("Videos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    viewModeButton
                    addVideoButton
                }
                
                ToolbarItemGroup(placement: .topBarLeading) {
                    if !selectedVideos.isEmpty {
                        batchActionsButton
                    }
                }
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotosPickerSheet { video in
                    // Handle imported video
                    videoManager.queueForSync(video)
                }
            }
            .fullScreenCover(item: $showingVideoPlayer) { video in
                VideoPlayerView(video: video) {
                    showingVideoPlayer = nil
                }
            }
            .confirmationDialog(
                "Batch Actions",
                isPresented: $showingBatchActions,
                titleVisibility: .visible
            ) {
                batchActionButtons
            }
        }
    }
    
    // MARK: - Subviews
    
    private var searchAndFilterBar: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search videos...", text: $videoManager.searchText)
                    .textFieldStyle(.plain)
                
                if !videoManager.searchText.isEmpty {
                    Button("Clear") {
                        videoManager.searchText = ""
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: "Highlights",
                        isSelected: videoManager.showHighlightsOnly,
                        systemImage: "star.fill"
                    ) {
                        videoManager.showHighlightsOnly.toggle()
                    }
                    
                    ForEach(videoManager.allTags, id: \.self) { tag in
                        FilterChip(
                            title: tag,
                            isSelected: videoManager.selectedTags.contains(tag)
                        ) {
                            if videoManager.selectedTags.contains(tag) {
                                videoManager.selectedTags.remove(tag)
                            } else {
                                videoManager.selectedTags.insert(tag)
                            }
                        }
                    }
                    
                    Menu("Sort") {
                        Picker("Sort by", selection: $videoManager.sortOption) {
                            ForEach(UnifiedVideoManager.SortOption.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var syncStatusBanner: some View {
        HStack {
            Image(systemName: "icloud.and.arrow.up")
                .foregroundColor(.blue)
            
            Text("\(videoManager.storageInfo.syncPending) videos pending sync")
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button("Sync All") {
                Task {
                    await videoManager.syncManager.performFullSync()
                }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.blue.opacity(0.1))
    }
    
    private var videoContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if videoManager.isLoading {
                    loadingView
                } else if videoManager.filteredVideos.isEmpty {
                    emptyStateView
                } else {
                    switch viewMode {
                    case .grid:
                        videoGrid
                    case .list:
                        videoList
                    }
                }
            }
            .padding(.horizontal)
        }
        .refreshable {
            await videoManager.syncManager.performFullSync()
        }
    }
    
    private var videoGrid: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 160), spacing: 12)
        ], spacing: 16) {
            ForEach(videoManager.filteredVideos) { video in
                VideoGridCard(
                    video: video,
                    isSelected: selectedVideos.contains(video.id),
                    onTap: { handleVideoTap(video) },
                    onLongPress: { toggleSelection(video.id) }
                )
            }
        }
    }
    
    private var videoList: some View {
        LazyVStack(spacing: 8) {
            ForEach(videoManager.filteredVideos) { video in
                VideoListRow(
                    video: video,
                    isSelected: selectedVideos.contains(video.id),
                    onTap: { handleVideoTap(video) },
                    onToggleSelection: { toggleSelection(video.id) }
                )
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading videos...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Videos Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Import videos from your Photos library or record new ones to get started.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Import Videos") {
                showingPhotoPicker = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 100)
    }
    
    // MARK: - Toolbar Items
    
    private var viewModeButton: some View {
        Button(action: { toggleViewMode() }) {
            Image(systemName: viewMode.icon)
        }
    }
    
    private var addVideoButton: some View {
        Menu {
            Button("Import from Photos", systemImage: "photo.on.rectangle") {
                showingPhotoPicker = true
            }
            
            Button("Record Video", systemImage: "video") {
                // TODO: Implement camera recording
            }
        } label: {
            Image(systemName: "plus")
        }
    }
    
    private var batchActionsButton: some View {
        Button("\(selectedVideos.count)") {
            showingBatchActions = true
        }
        .foregroundColor(.blue)
        .fontWeight(.semibold)
    }
    
    @ViewBuilder
    private var batchActionButtons: some View {
        Button("Upload Selected", systemImage: "icloud.and.arrow.up") {
            uploadSelectedVideos()
        }
        
        Button("Mark as Highlights", systemImage: "star") {
            markSelectedAsHighlights()
        }
        
        Button("Delete Selected", systemImage: "trash", role: .destructive) {
            deleteSelectedVideos()
        }
        
        Button("Cancel", role: .cancel) {
            clearSelection()
        }
    }
    
    // MARK: - Actions
    
    private func handleVideoTap(_ video: VideoRecord) {
        if !selectedVideos.isEmpty {
            toggleSelection(video.id)
        } else {
            showingVideoPlayer = video
        }
    }
    
    private func toggleSelection(_ videoId: String) {
        if selectedVideos.contains(videoId) {
            selectedVideos.remove(videoId)
        } else {
            selectedVideos.insert(videoId)
        }
    }
    
    private func clearSelection() {
        selectedVideos.removeAll()
    }
    
    private func toggleViewMode() {
        viewMode = viewMode == .grid ? .list : .grid
    }
    
    private func uploadSelectedVideos() {
        let videosToUpload = videoManager.videos.filter { selectedVideos.contains($0.id) }
        Task {
            await videoManager.uploadVideos(videosToUpload)
        }
        clearSelection()
    }
    
    private func markSelectedAsHighlights() {
        Task {
            await videoManager.markAsHighlights(Array(selectedVideos))
        }
        clearSelection()
    }
    
    private func deleteSelectedVideos() {
        let videosToDelete = videoManager.videos.filter { selectedVideos.contains($0.id) }
        Task {
            await videoManager.deleteVideos(videosToDelete)
        }
        clearSelection()
    }
}

// MARK: - Supporting Views

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let systemImage: String?
    let action: () -> Void
    
    init(title: String, isSelected: Bool, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.systemImage = systemImage
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                }
                
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? .blue : .clear)
            .foregroundColor(isSelected ? .white : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? .clear : .secondary, lineWidth: 1)
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct VideoGridCard: View {
    let video: VideoRecord
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.regularMaterial)
                        .aspectRatio(16/9, contentMode: .fit)
                    
                    if let thumbnailPath = video.thumbnailPath,
                       let thumbnailImage = UIImage(contentsOfFile: thumbnailPath) {
                        Image(uiImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                            .cornerRadius(8)
                    } else {
                        Image(systemName: "video")
                            .font(.title)
                            .foregroundColor(.secondary)
                    }
                    
                    // Duration badge
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatDuration(video.duration))
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.7))
                                .cornerRadius(4)
                                .padding(4)
                        }
                    }
                    
                    // Selection indicator
                    if isSelected {
                        VStack {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                    .background(.white)
                                    .clipShape(Circle())
                                    .padding(8)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                    
                    // Status indicators
                    VStack {
                        HStack {
                            if video.isHighlight {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .padding(4)
                            }
                            
                            Spacer()
                            
                            syncStatusIcon(video.syncStatus)
                        }
                        Spacer()
                    }
                }
                
                // Title and metadata
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text(ByteCountFormatter.string(fromByteCount: video.fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? .blue : .clear, lineWidth: 2)
        )
        .onLongPressGesture {
            onLongPress()
        }
    }
    
    @ViewBuilder
    private func syncStatusIcon(_ status: VideoRecord.SyncStatus) -> some View {
        switch status {
        case .syncing:
            ProgressView()
                .scaleEffect(0.7)
                .padding(4)
        case .synced:
            Image(systemName: "icloud.fill")
                .foregroundColor(.green)
                .padding(4)
        case .syncFailed:
            Image(systemName: "icloud.slash")
                .foregroundColor(.red)
                .padding(4)
        case .notSynced:
            Image(systemName: "icloud")
                .foregroundColor(.gray)
                .padding(4)
        case .syncConflict:
            Image(systemName: "exclamationmark.icloud")
                .foregroundColor(.orange)
                .padding(4)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct VideoListRow: View {
    let video: VideoRecord
    let isSelected: Bool
    let onTap: () -> Void
    let onToggleSelection: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection button
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.regularMaterial)
                        .frame(width: 60, height: 40)
                    
                    if let thumbnailPath = video.thumbnailPath,
                       let thumbnailImage = UIImage(contentsOfFile: thumbnailPath) {
                        Image(uiImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 40)
                            .clipped()
                            .cornerRadius(6)
                    } else {
                        Image(systemName: "video")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Video info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(video.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if video.isHighlight {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                    }
                    
                    HStack {
                        Text(formatDuration(video.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(ByteCountFormatter.string(fromByteCount: video.fileSize, countStyle: .file))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        syncStatusIcon(video.syncStatus)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(isSelected ? .blue.opacity(0.1) : .clear)
    }
    
    @ViewBuilder
    private func syncStatusIcon(_ status: VideoRecord.SyncStatus) -> some View {
        switch status {
        case .syncing:
            ProgressView()
                .scaleEffect(0.6)
        case .synced:
            Image(systemName: "icloud.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .syncFailed:
            Image(systemName: "icloud.slash")
                .foregroundColor(.red)
                .font(.caption)
        case .notSynced:
            Image(systemName: "icloud")
                .foregroundColor(.gray)
                .font(.caption)
        case .syncConflict:
            Image(systemName: "exclamationmark.icloud")
                .foregroundColor(.orange)
                .font(.caption)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PhotosPickerSheet: View {
    let onVideoImported: (VideoRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    
    var body: some View {
        NavigationStack {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 5,
                matching: .videos
            ) {
                VStack(spacing: 20) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Select Videos")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Choose up to 5 videos from your Photos library")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Import Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.3)
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            
                            Text("Importing Videos...")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .ignoresSafeArea()
                }
            }
            .onChange(of: selectedItems) { newItems in
                if !newItems.isEmpty {
                    importVideos(newItems)
                }
            }
        }
    }
    
    private func importVideos(_ items: [PhotosPickerItem]) {
        isImporting = true
        
        Task {
            let videoManager = UnifiedVideoManager.shared
            
            for item in items {
                let result = await videoManager.importVideo(from: item)
                
                switch result {
                case .success(let video):
                    onVideoImported(video)
                case .failure:
                    // Error is already handled by the video manager
                    break
                }
            }
            
            await MainActor.run {
                isImporting = false
                dismiss()
            }
        }
    }
}

struct VideoPlayerView: View {
    let video: VideoRecord
    let onDismiss: () -> Void
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let localURL = video.localURL {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        player = AVPlayer(url: localURL)
                        player?.play()
                    }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }
            }
            
            VStack {
                HStack {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

#Preview {
    VideoManagementView()
}