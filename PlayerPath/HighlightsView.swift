//
//  HighlightsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import Foundation

struct HighlightsView: View {
    let athlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @State private var selectedClip: VideoClip?
    @State private var showingVideoPlayer = false
    @State private var showingDeleteAlert = false
    @State private var clipToDelete: VideoClip?
    @State private var editMode: EditMode = .inactive
    
    var highlights: [VideoClip] {
        athlete?.videoClips.filter { $0.isHighlight }.sorted { (lhs, rhs) in
            let lhsDate = lhs.createdAt ?? .distantPast
            let rhsDate = rhs.createdAt ?? .distantPast
            return lhsDate > rhsDate
        } ?? []
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if highlights.isEmpty {
                    EmptyHighlightsView()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 15) {
                            ForEach(highlights) { clip in
                                VStack(spacing: 8) {
                                    HighlightCard(
                                        clip: clip,
                                        editMode: editMode,
                                        onTap: {
                                            if editMode == .inactive {
                                                selectedClip = clip
                                                showingVideoPlayer = true
                                            }
                                        },
                                        onDelete: {
                                            clipToDelete = clip
                                            showingDeleteAlert = true
                                        }
                                    )
                                    
                                    // Cloud progress for highlights
                                    if editMode == .inactive {
                                        SimpleCloudProgressView(clip: clip)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Highlights")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: SimpleCloudStorageView()) {
                        Image(systemName: "icloud.and.arrow.up")
                    }
                }
                
                if !highlights.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(editMode == .inactive ? "Edit" : "Done") {
                            withAnimation {
                                editMode = editMode == .inactive ? .active : .inactive
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let clip = selectedClip {
                VideoPlayerView(clip: clip)
            }
        }
        .alert("Delete Highlight", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                clipToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let clip = clipToDelete {
                    deleteHighlight(clip)
                }
                clipToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this highlight? This action cannot be undone.")
        }
    }
    
    private func deleteHighlight(_ clip: VideoClip) {
        withAnimation {
            // Delete the video file
            if FileManager.default.fileExists(atPath: clip.filePath) {
                try? FileManager.default.removeItem(atPath: clip.filePath)
                print("Deleted video file: \(clip.filePath)")
            }
            
            // Delete the thumbnail file
            if let thumbnailPath = clip.thumbnailPath {
                do {
                    try FileManager.default.removeItem(atPath: thumbnailPath)
                    print("Deleted thumbnail file: \(thumbnailPath)")
                    
                    // Remove from cache
                    Task { @MainActor in
                        ThumbnailCache.shared.removeThumbnail(at: thumbnailPath)
                    }
                } catch {
                    print("Failed to delete thumbnail file: \(error)")
                }
            }
            
            // Remove from athlete's video clips array
            if let athlete = athlete,
               let index = athlete.videoClips.firstIndex(of: clip) {
                athlete.videoClips.remove(at: index)
            }
            
            // Remove from game's video clips array if applicable
            if let game = clip.game,
               let index = game.videoClips.firstIndex(of: clip) {
                game.videoClips.remove(at: index)
            }
            
            // Remove from practice's video clips array if applicable
            if let practice = clip.practice,
               let index = practice.videoClips.firstIndex(of: clip) {
                practice.videoClips.remove(at: index)
            }
            
            // Delete any associated play results
            if let playResult = clip.playResult {
                modelContext.delete(playResult)
            }
            
            // Delete the clip itself
            modelContext.delete(clip)
            
            do {
                try modelContext.save()
                print("Successfully deleted highlight")
            } catch {
                print("Failed to delete highlight: \(error)")
            }
        }
    }
}

struct EmptyHighlightsView: View {
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "star")
                .font(.system(size: 80))
                .foregroundColor(.yellow)
            
            Text("No Highlights Yet")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Record some great plays! Singles, doubles, triples, and home runs automatically become highlights")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct HighlightCard: View {
    let clip: VideoClip
    let editMode: EditMode
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Video thumbnail area with proper thumbnail loading
                ZStack {
                    Group {
                        if let thumbnail = thumbnailImage {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 120)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: playResultGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 120)
                                .overlay(
                                    VStack(spacing: 8) {
                                        if isLoadingThumbnail {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(1.2)
                                        } else {
                                            Image(systemName: "video")
                                                .font(.title2)
                                                .foregroundColor(.white)
                                            
                                            Text("Loading...")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                    }
                                )
                        }
                    }
                    
                    // Delete button in edit mode
                    if editMode == .active {
                        VStack {
                            HStack {
                                Button(action: onDelete) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.red)
                                        .background(Circle().fill(Color.white))
                                }
                                .padding(8)
                                
                                Spacer()
                            }
                            
                            Spacer()
                        }
                    } else {
                        // Play button overlay (only in normal mode)
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.title3)
                                    .foregroundColor(.white)
                            )
                    }
                    
                    // Play result badge in top-right corner (always visible)
                    VStack {
                        HStack {
                            Spacer()
                            
                            if let playResult = clip.playResult {
                                VStack(spacing: 2) {
                                    Image(systemName: playResultIcon(for: playResult.type))
                                        .foregroundColor(.white)
                                        .font(.caption)
                                    
                                    Text(playResultAbbreviation(for: playResult.type))
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(playResultColor(for: playResult.type))
                                .cornerRadius(8)
                                .padding(.top, editMode == .active ? 40 : 8) // Adjust for delete button
                                .padding(.trailing, 8)
                            }
                        }
                        
                        Spacer()
                        
                        // Highlight star in bottom-left corner (always visible)
                        HStack {
                            Image(systemName: "star.fill")
                                .font(.title3)
                                .foregroundColor(.yellow)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.6))
                                        .frame(width: 32, height: 32)
                                )
                                .padding(.bottom, 8)
                                .padding(.leading, 8)
                            
                            Spacer()
                        }
                    }
                }
                
                // Info overlay at bottom
                VStack(alignment: .leading, spacing: 4) {
                    if let playResult = clip.playResult {
                        Text(playResult.type.rawValue)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    if let game = clip.game {
                        Text("vs \(game.opponent)")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        
                        Text((game.date ?? Date()), style: .date)
                    } else {
                        Text("Practice")
                            .font(.subheadline)
                            .foregroundColor(.green)
                        
                        Text((clip.createdAt ?? Date()), style: .date)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .scaleEffect(editMode == .active ? 0.95 : 1.0) // Slightly smaller in edit mode
        .animation(.easeInOut(duration: 0.2), value: editMode)
        .task {
            await loadThumbnail()
        }
        .onAppear {
            // If we already have the image loaded, don't reload
            if thumbnailImage == nil {
                Task {
                    await loadThumbnail()
                }
            }
        }
    }
    
    @MainActor
    private func loadThumbnail() async {
        // Skip if already loading or already have image
        guard !isLoadingThumbnail, thumbnailImage == nil else { return }
        
        // Check if we have a thumbnail path
        guard let thumbnailPath = clip.thumbnailPath else {
            // Generate thumbnail if none exists
            await generateMissingThumbnail()
            return
        }
        
        isLoadingThumbnail = true
        
        do {
            // Load thumbnail asynchronously using the same cache system
            let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath)
            thumbnailImage = image
        } catch {
            print("Failed to load thumbnail in HighlightCard: \(error)")
            // Try to regenerate thumbnail
            await generateMissingThumbnail()
        }
        
        isLoadingThumbnail = false
    }
    
    private func generateMissingThumbnail() async {
        print("Generating missing thumbnail for highlight: \(clip.fileName)")
        
        let videoURL = URL(fileURLWithPath: clip.filePath)
        let result = await VideoFileManager.generateThumbnail(from: videoURL)
        
        await MainActor.run {
            switch result {
            case .success(let thumbnailPath):
                clip.thumbnailPath = thumbnailPath
                Task {
                    await loadThumbnail()
                }
            case .failure(let error):
                print("Failed to generate thumbnail in HighlightCard: \(error)")
                isLoadingThumbnail = false
            }
        }
    }
    
    private var playResultGradient: [Color] {
        guard let playResult = clip.playResult else { return [.gray, .gray.opacity(0.7)] }
        
        switch playResult.type {
        case .single:
            return [.green, .green.opacity(0.7)]
        case .double:
            return [.blue, .blue.opacity(0.7)]
        case .triple:
            return [.orange, .orange.opacity(0.7)]
        case .homeRun:
            return [.red, .red.opacity(0.7)]
        default:
            return [.gray, .gray.opacity(0.7)]
        }
    }
    
    // Helper functions for play result styling
    private func playResultIcon(for type: PlayResultType) -> String {
        switch type {
        case .single:
            return "1.circle.fill"
        case .double:
            return "2.circle.fill"
        case .triple:
            return "3.circle.fill"
        case .homeRun:
            return "4.circle.fill"
        case .walk:
            return "figure.walk"
        case .strikeout:
            return "k.circle.fill"
        case .groundOut:
            return "arrow.down.circle.fill"
        case .flyOut:
            return "arrow.up.circle.fill"
        }
    }
    
    private func playResultAbbreviation(for type: PlayResultType) -> String {
        switch type {
        case .single:
            return "1B"
        case .double:
            return "2B"
        case .triple:
            return "3B"
        case .homeRun:
            return "HR"
        case .walk:
            return "BB"
        case .strikeout:
            return "K"
        case .groundOut:
            return "GO"
        case .flyOut:
            return "FO"
        }
    }
    
    private func playResultColor(for type: PlayResultType) -> Color {
        switch type {
        case .single:
            return .green
        case .double:
            return .blue
        case .triple:
            return .orange
        case .homeRun:
            return .red
        case .walk:
            return .cyan
        case .strikeout:
            return .red.opacity(0.8)
        case .groundOut, .flyOut:
            return .gray
        }
    }
}

// MARK: - Temporary Simple Cloud Progress View
struct SimpleCloudProgressView: View {
    let clip: VideoClip
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: cloudStatusIcon)
                .foregroundColor(cloudStatusColor)
                .font(.caption)
            
            Text(cloudStatusText)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if clip.needsUpload {
                Button("Upload") {
                    // TODO: Implement upload functionality
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var cloudStatusIcon: String {
        if clip.isUploaded && clip.isAvailableOffline {
            return "icloud.and.arrow.down.fill"
        } else if clip.isUploaded {
            return "icloud.fill"
        } else if clip.needsUpload {
            return "icloud.and.arrow.up"
        } else {
            return "externaldrive.fill"
        }
    }
    
    private var cloudStatusColor: Color {
        if clip.isUploaded && clip.isAvailableOffline {
            return .green
        } else if clip.isUploaded {
            return .blue
        } else if clip.needsUpload {
            return .orange
        } else {
            return .gray
        }
    }
    
    private var cloudStatusText: String {
        if clip.isUploaded && clip.isAvailableOffline {
            return "Available Offline"
        } else if clip.isUploaded {
            return "In Cloud"
        } else if clip.needsUpload {
            return "Ready to Upload"
        } else {
            return "Local Only"
        }
    }
}



// MARK: - Simple Cloud Storage View
struct SimpleCloudStorageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var pendingUploads: [VideoClip]
    
    init() {
        self._pendingUploads = Query(
            filter: #Predicate<VideoClip> { $0.needsUpload },
            sort: [SortDescriptor(\VideoClip.createdAt, order: .reverse)]
        )
    }
    
    var body: some View {
        NavigationStack {
            List {
                if pendingUploads.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.icloud")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                        
                        Text("All videos are up to date")
                            .font(.title3)
                            .fontWeight(.medium)
                        
                        Text("Your highlights and videos are synchronized with cloud storage.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .listRowBackground(Color.clear)
                } else {
                    Section("Videos Ready to Upload") {
                        ForEach(pendingUploads) { clip in
                            HStack {
                                // Thumbnail placeholder
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 50, height: 38)
                                    .overlay(
                                        Image(systemName: "video")
                                            .foregroundColor(.gray)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    if let playResult = clip.playResult {
                                        Text(playResult.type.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    } else {
                                        Text(clip.fileName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    
                                    if let game = clip.game {
                                        Text("vs \(game.opponent)")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    } else {
                                        Text("Practice")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                Spacer()
                                
                                Button("Upload") {
                                    // TODO: Implement upload functionality
                                    print("Upload requested for: \(clip.fileName)")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    
                    Section {
                        Button("Upload All Videos") {
                            // TODO: Implement bulk upload
                            print("Bulk upload requested for \(pendingUploads.count) videos")
                        }
                        .disabled(pendingUploads.isEmpty)
                    }
                }
            }
            .navigationTitle("Cloud Storage")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

extension DateFormatter {
    static let pp_shortDate: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .none
        return df
    }()
}

#Preview {
    HighlightsView(athlete: nil)
}

