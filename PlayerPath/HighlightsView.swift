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

    @State private var searchText: String = ""
    enum Filter: String, CaseIterable, Identifiable { case all, game, practice; var id: String { rawValue } }
    @State private var filter: Filter = .all
    enum SortOrder: String, CaseIterable, Identifiable { case newest, oldest; var id: String { rawValue } }
    @State private var sortOrder: SortOrder = .newest
    @State private var selection = Set<VideoClip.ID>()
    @State private var recentlyDeleted: [VideoClip] = []
    @State private var showingUndoAlert = false
    
    var highlights: [VideoClip] {
        let base = athlete?.videoClips.filter { $0.isHighlight } ?? []
        let filteredByType: [VideoClip] = base.filter { clip in
            switch filter {
            case .all: return true
            case .game: return clip.game != nil
            case .practice: return clip.game == nil
            }
        }
        let filteredBySearch: [VideoClip]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filteredBySearch = filteredByType
        } else {
            let q = searchText.lowercased()
            filteredBySearch = filteredByType.filter { clip in
                let opponent = clip.game?.opponent.lowercased() ?? ""
                let result = clip.playResult?.type.displayName.lowercased() ?? ""
                let fileName = clip.fileName.lowercased()
                return opponent.contains(q) || result.contains(q) || fileName.contains(q)
            }
        }
        let sorted = filteredBySearch.sorted { lhs, rhs in
            let l = lhs.createdAt ?? .distantPast
            let r = rhs.createdAt ?? .distantPast
            return sortOrder == .newest ? (l > r) : (l < r)
        }
        return sorted
    }
    
    var body: some View {
        contentView
            .tabRootNavigationBar(title: athlete?.name ?? "Highlights")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                toolbarContent
            }
            .environment(\.editMode, $editMode)
        .sheet(isPresented: $showingVideoPlayer) {
            if let clip: VideoClip = selectedClip {
                VideoPlayerView(clip: clip)
            }
        }
        .alert("Delete Highlight", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                clipToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let clip = clipToDelete {
                    stageDelete(clip)
                }
                clipToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this highlight? This action cannot be undone.")
        }
        .alert("Highlight deleted", isPresented: $showingUndoAlert) {
            Button("Undo", role: .cancel) {
                undoRecentDelete()
            }
            Button("OK", role: .none) { finalizeStagedDeletes() }
        } message: {
            Text("You can undo this action.")
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if highlights.isEmpty {
            EmptyHighlightsView()
        } else {
            highlightGridView
        }
    }
    
    private var highlightGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 15, alignment: .top)], spacing: 15) {
                ForEach(highlights) { clip in
                    highlightItemView(for: clip)
                }
            }
            .padding()
        }
    }
    
    private func highlightItemView(for clip: VideoClip) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 8) {
                HighlightCard(
                    clip: clip,
                    editMode: editMode,
                    onTap: {
                        if editMode == .inactive {
                            selectedClip = clip
                            showingVideoPlayer = true
                        } else {
                            toggleSelection(clip)
                        }
                    },
                    onDelete: {
                        clipToDelete = clip
                        showingDeleteAlert = true
                    }
                )
                .contextMenu {
                    contextMenuItems(for: clip)
                }
                if editMode == .inactive {
                    SimpleCloudProgressView(clip: clip)
                }
            }
            if editMode == .active {
                selectionButton(for: clip)
            }
        }
    }
    
    @ViewBuilder
    private func contextMenuItems(for clip: VideoClip) -> some View {
        Button {
            selectedClip = clip
            showingVideoPlayer = true
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        Button {
            // Toggle highlight flag if supported
            clip.isHighlight.toggle()
            try? modelContext.save()
        } label: {
            Label(clip.isHighlight ? "Remove Highlight" : "Mark as Highlight", systemImage: "star")
        }
        Button(role: .destructive) {
            clipToDelete = clip
            showingDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    private func selectionButton(for clip: VideoClip) -> some View {
        Button(action: { toggleSelection(clip) }) {
            Image(systemName: selection.contains(clip.id) ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.hierarchical)
                .font(.title2)
                .foregroundStyle(selection.contains(clip.id) ? .blue : .secondary)
                .padding(8)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            NavigationLink(destination: SimpleCloudStorageView()) {
                Image(systemName: "icloud.and.arrow.up")
            }
        }
        ToolbarItem(placement: .principal) {
            titleMenu
        }
        if !highlights.isEmpty {
            ToolbarItem(placement: .navigationBarTrailing) {
                editButton
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            if editMode == .active {
                bottomBarButtons
            }
        }
    }
    
    private var titleMenu: some View {
        Menu {
            Picker("Filter", selection: $filter) {
                Text("All").tag(Filter.all)
                Text("Games").tag(Filter.game)
                Text("Practice").tag(Filter.practice)
            }
            Picker("Sort", selection: $sortOrder) {
                Text("Newest").tag(SortOrder.newest)
                Text("Oldest").tag(SortOrder.oldest)
            }
        } label: {
            HStack(spacing: 6) {
                Text(athlete?.name ?? "Highlights")
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var editButton: some View {
        Button(editMode == .inactive ? "Select" : (selection.isEmpty ? "Done" : "Done (\(selection.count))")) {
            withAnimation { toggleEditMode() }
        }
    }
    
    @ViewBuilder
    private var bottomBarButtons: some View {
        Button(role: .destructive) {
            batchDeleteSelected()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(selection.isEmpty)
        Spacer()
        Button {
            selection.removeAll()
        } label: {
            Label("Clear", systemImage: "xmark.circle")
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

    private func toggleEditMode() {
        if editMode == .inactive {
            editMode = .active
        } else {
            editMode = .inactive
            selection.removeAll()
        }
    }

    private func toggleSelection(_ clip: VideoClip) {
        if selection.contains(clip.id) {
            selection.remove(clip.id)
        } else {
            selection.insert(clip.id)
        }
    }

    private func batchDeleteSelected() {
        let clips = highlights.filter { selection.contains($0.id) }
        guard !clips.isEmpty else { return }
        for clip in clips { stageDelete(clip) }
        selection.removeAll()
        withAnimation { editMode = .inactive }
    }
    
    private func stageDelete(_ clip: VideoClip) {
        // Remove from UI immediately but delay file/model deletion to allow undo
        recentlyDeleted.append(clip)
        // Remove references so it disappears from lists
        if let athlete = athlete, let idx = athlete.videoClips.firstIndex(of: clip) { athlete.videoClips.remove(at: idx) }
        if let game = clip.game, let idx = game.videoClips.firstIndex(of: clip) { game.videoClips.remove(at: idx) }
        if let practice = clip.practice, let idx = practice.videoClips.firstIndex(of: clip) { practice.videoClips.remove(at: idx) }
        // Show undo alert
        showingUndoAlert = true
    }

    private func undoRecentDelete() {
        // Reinsert staged items back to their relationships
        for clip in recentlyDeleted {
            if let athlete = athlete {
                if !athlete.videoClips.contains(clip) { athlete.videoClips.append(clip) }
            }
            if let game = clip.game {
                if !game.videoClips.contains(clip) { game.videoClips.append(clip) }
            }
            if let practice = clip.practice {
                if !practice.videoClips.contains(clip) { practice.videoClips.append(clip) }
            }
        }
        recentlyDeleted.removeAll()
    }

    private func finalizeStagedDeletes() {
        guard !recentlyDeleted.isEmpty else { return }
        for clip in recentlyDeleted {
            deleteHighlight(clip)
        }
        recentlyDeleted.removeAll()
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
                GeometryReader { geometry in
                    ZStack {
                        Group {
                            if let thumbnail = thumbnailImage {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
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
                            .transition(.scale.combined(with: .opacity))
                            .animation(.easeInOut(duration: 0.15), value: editMode)
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
                }
                .aspectRatio(9/16, contentMode: .fit) // Portrait video aspect ratio
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                
                // Info overlay at bottom
                VStack(alignment: .leading, spacing: 4) {
                    if let playResult = clip.playResult {
                        Text(playResult.type.displayName)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(editMode == .active ? "Tap to select. Use bottom toolbar to delete." : "Tap to play the highlight.")
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .scaleEffect(editMode == .active ? 0.95 : 1.0) // Slightly smaller in edit mode
        .animation(.easeInOut(duration: 0.2), value: editMode)
        .task {
            await loadThumbnail()
        }
    }
    
    private var accessibilityLabel: String {
        var parts: [String] = []
        if let pr = clip.playResult { parts.append(pr.type.displayName) }
        if let game = clip.game { parts.append("vs \(game.opponent)") }
        else { parts.append("Practice") }
        let dateText = DateFormatter.pp_shortDate.string(from: (clip.createdAt ?? Date()))
        parts.append(dateText)
        return parts.joined(separator: ", ")
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
                                        Text(playResult.type.displayName)
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
