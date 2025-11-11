//
//  VideoClipsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import AVKit
import Foundation
import UIKit

struct VideoClipsView: View {
    let athlete: Athlete?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingVideoRecorder = false
    @State private var selectedClip: VideoClip?
    @State private var showingVideoPlayer = false
    @State private var liveGameForRecording: Game?
    @State private var showingPracticePicker = false
    @State private var clipPendingCopy: VideoClip?
    @State private var searchText: String = ""
    @State private var clipToShare: VideoClip?

    private enum ClipsSheet: Identifiable {
        case recorder
        case player(VideoClip)
        var id: String {
            switch self {
            case .recorder: return "recorder"
            case .player(let clip): return "player-\(clip.id.uuidString)"
            }
        }
    }

    @State private var activeSheet: ClipsSheet?
    
    var videoClips: [VideoClip] {
        guard let clips = athlete?.videoClips else { return [] }
        return clips.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?):
                if l == r { return lhs.id.uuidString < rhs.id.uuidString }
                return l > r
            case (nil, nil):
                return lhs.id.uuidString < rhs.id.uuidString
            case (nil, _?):
                return false // nil dates are considered older (go last)
            case (_?, nil):
                return true
            }
        }
    }
    
    var filteredClips: [VideoClip] {
        let base: [VideoClip] = videoClips
        let query: String = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return base }

        return base.filter { clip in
            // Precompute searchable fields as simple Strings
            let opponent: String = (clip.game?.opponent ?? "").lowercased()

            let practiceDateString: String = {
                if let date = clip.practice?.date {
                    return DateFormatter.mediumDateTime.string(from: date).lowercased()
                } else {
                    return ""
                }
            }()

            let resultText: String = {
                if let result = clip.playResult?.type.displayName {
                    return result.lowercased()
                } else {
                    return "unrecorded"
                }
            }()

            let fileName: String = clip.fileName.lowercased()

            // Perform individual checks with clearly typed values
            let matchesOpponent: Bool = opponent.contains(query)
            if matchesOpponent { return true }

            let matchesPracticeDate: Bool = practiceDateString.contains(query)
            if matchesPracticeDate { return true }

            let matchesResult: Bool = resultText.contains(query)
            if matchesResult { return true }

            let matchesFileName: Bool = fileName.contains(query)
            if matchesFileName { return true }

            return false
        }
    }
    
    var body: some View {
        Group {
            if videoClips.isEmpty {
                EmptyVideoClipsView {
                    activeSheet = .recorder
                }
            } else {
                VideoClipsListSection(
                    filteredClips: filteredClips,
                    onPlay: { clip in activeSheet = .player(clip) },
                    onCopy: { clip in clipPendingCopy = clip; showingPracticePicker = true },
                    onShare: { clip in clipToShare = clip },
                    onToggleHighlight: { clip in toggleHighlight(for: clip) },
                    onDeleteIDs: { ids in deleteClips(with: ids) }
                )
            }
        }
        .navigationTitle("Video Clips")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    NotificationCenter.default.post(name: .switchTab, object: 0)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back to Dashboard")
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    CloudProgressView()
                } label: {
                    Image(systemName: "icloud.and.arrow.up")
                        .accessibilityLabel("Cloud Storage")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { activeSheet = .recorder }) {
                    Image(systemName: "video.badge.plus")
                        .accessibilityLabel("Record Video")
                }
            }
            
            if !videoClips.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .recorder:
                VideoRecorderView_Refactored(
                    athlete: athlete,
                    game: liveGameForRecording ?? athlete?.games.first { $0.isLive }
                )
                .presentationDetents([.medium, .large])
            case .player(let clip):
                VideoPlayerView(clip: clip)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showingPracticePicker) {
            if let athlete = athlete, let clip = clipPendingCopy {
                PracticePickerSheet(athlete: athlete) { selectedPractice in
                    Task { await copyClip(clip, to: selectedPractice) }
                }
            } else {
                Text("No athlete or clip selected")
                    .padding()
            }
        }
        .sheet(item: $clipToShare) { clip in
            let url = URL(fileURLWithPath: clip.filePath)
            ActivityView(activityItems: [url])
                .presentationDetents([.medium, .large])
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentVideoRecorder)) { notification in
            // Handle live game context from dashboard
            if let game = notification.object as? Game {
                liveGameForRecording = game
                print("🎮 Received live game for recording: \(game.opponent)")
            } else if let payload = notification.object as? [String: Any],
                      let idString = payload["liveGameID"] as? String,
                      let uuid = UUID(uuidString: idString) {
                liveGameForRecording = athlete?.games.first(where: { $0.id == uuid })
                print("🎮 Received game ID for recording: \(idString)")
            } else {
                liveGameForRecording = nil
                print("🎬 No live game context - regular recording")
            }
            activeSheet = .recorder
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search clips")
        .refreshable { await refreshCloudStatus() }
    }
    
    @MainActor
    private func deleteVideoClips(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let clip = videoClips[index]
                
                // Remove from athlete's collection if present
                if let athlete = clip.athlete,
                   let idx = athlete.videoClips.firstIndex(of: clip) {
                    athlete.videoClips.remove(at: idx)
                }
                
                // Delete associated play result
                if let playResult = clip.playResult {
                    modelContext.delete(playResult)
                }
                
                modelContext.delete(clip)
                
                // Kick off file deletions asynchronously
                self.deleteFiles(for: clip)
            }
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to delete video clips: \(error)")
            }
        }
    }
    
    @MainActor
    private func deleteClips(with ids: [UUID]) {
        withAnimation {
            let clipsToDelete = videoClips.filter { ids.contains($0.id) }
            for clip in clipsToDelete {
                if let athlete = clip.athlete, let idx = athlete.videoClips.firstIndex(of: clip) {
                    athlete.videoClips.remove(at: idx)
                }
                if let playResult = clip.playResult { modelContext.delete(playResult) }
                modelContext.delete(clip)
                self.deleteFiles(for: clip)
            }
            do { try modelContext.save() } catch { print("Failed to delete video clips: \(error)") }
        }
    }
    
    private func deleteFiles(for clip: VideoClip) {
        Task.detached(priority: .utility) {
            let fileURL = URL(fileURLWithPath: clip.filePath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do { try FileManager.default.removeItem(at: fileURL) }
                catch { print("Error deleting video file: \(error)") }
            }
            
            if let thumbnailPath = clip.thumbnailPath {
                let thumbURL = URL(fileURLWithPath: thumbnailPath)
                if FileManager.default.fileExists(atPath: thumbURL.path) {
                    do { try FileManager.default.removeItem(at: thumbURL) }
                    catch { print("Error deleting thumbnail: \(error)") }
                }
                await MainActor.run {
                    ThumbnailCache.shared.removeThumbnail(at: thumbnailPath)
                }
            }
        }
    }
    
    @MainActor
    private func copyClip(_ clip: VideoClip, to practice: Practice) async {
        guard let athlete = athlete else { return }
        // Create a new VideoClip using designated initializer, then copy fields as needed
        let newClip = VideoClip(fileName: clip.fileName, filePath: clip.filePath)
        newClip.thumbnailPath = clip.thumbnailPath
        newClip.createdAt = Date()
        newClip.isHighlight = clip.isHighlight
        newClip.isUploaded = false
        newClip.playResult = clip.playResult // set to nil if you prefer not to copy result
        newClip.athlete = athlete
        newClip.practice = practice
        newClip.game = nil
        await MainActor.run {
            athlete.videoClips.append(newClip)
            practice.videoClips.append(newClip)
            modelContext.insert(newClip)
            do { try modelContext.save() } catch { print("Failed to copy clip to practice: \(error)") }
            Haptics.light()
            UIAccessibility.post(notification: .announcement, argument: "Clip copied to practice")
        }
    }
    
    private func cloudStatusText(for clip: VideoClip) -> String {
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
    
    private func refreshCloudStatus() async {
        // TODO: Refresh cloud statuses or re-validate thumbnails
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
    
    @MainActor
    private func toggleHighlight(for clip: VideoClip) {
        clip.isHighlight.toggle()
        do { try modelContext.save() } catch { print("Failed to toggle highlight: \(error)") }
        Haptics.light()
    }
}

private struct VideoClipsListSection: View {
    let filteredClips: [VideoClip]
    let onPlay: (VideoClip) -> Void
    let onCopy: (VideoClip) -> Void
    let onShare: (VideoClip) -> Void
    let onToggleHighlight: (VideoClip) -> Void
    let onDeleteIDs: ([UUID]) -> Void

    var body: some View {
        List {
            Section(
                header: Text("Clips (\(filteredClips.count))"),
                footer: Text("Swipe left to copy to practice or right to highlight.")
            ) {
                ForEach(filteredClips) { clip in
                    VideoClipListItem(clip: clip) {
                        onPlay(clip)
                    }
                    .contextMenu {
                        Button {
                            onCopy(clip)
                        } label: {
                            Label("Copy to Practice", systemImage: "doc.on.doc")
                        }
                        Button {
                            onShare(clip)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            onCopy(clip)
                        } label: {
                            Label("Copy to Practice", systemImage: "doc.on.doc")
                        }.tint(.green)
                        Button {
                            onShare(clip)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }.tint(.blue)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            onToggleHighlight(clip)
                        } label: {
                            Label(clip.isHighlight ? "Unhighlight" : "Highlight", systemImage: "star")
                        }
                        .tint(.yellow)
                    }

                    SimpleCloudIndicator(clip: clip)
                        .padding(.horizontal)
                        .accessibilityLabel("Cloud status: \(clip.cloudStatusText)")
                }
                .onDelete { offsets in
                    let idsToDelete: [UUID] = offsets.map { filteredClips[$0].id }
                    onDeleteIDs(idsToDelete)
                }
            }
        }
        .contentMargins(0, for: .scrollContent)
    }
}

struct EmptyVideoClipsView: View {
    let onRecordVideo: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "video")
                .font(.system(size: 80))
                .foregroundColor(.purple)
            
            Text("No Video Clips Yet")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Record your first video clip to start building your baseball journal")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Record Video") {
                Haptics.light()
                onRecordVideo()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .accessibilityLabel("Record Video")
        }
        .padding()
        .padding(.bottom, 120)
    }
}

struct VideoClipListItem: View {
    let clip: VideoClip
    let onTap: () -> Void
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Button(action: { onTap() }) {
            HStack(spacing: 12) {
                // Enhanced Thumbnail with Play Result Overlay
                ZStack(alignment: .bottomLeading) {
                    // Thumbnail Image
                    Group {
                        if let thumbnail = thumbnailImage {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 60)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 80, height: 60)
                                .overlay(
                                    VStack(spacing: 4) {
                                        if isLoadingThumbnail {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "video")
                                                .foregroundColor(.white)
                                                .font(.title3)
                                                .accessibilityHidden(true)
                                        }
                                        
                                        Text(isLoadingThumbnail ? "Loading..." : "No Preview")
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                    }
                                )
                        }
                    }
                    .cornerRadius(8)
                    .overlay(
                        // Play button overlay
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .foregroundColor(.white)
                                    .font(.caption)
                                    .accessibilityHidden(true)
                            )
                    )
                    
                    // Play Result Badge Overlay
                    if let playResult = clip.playResult {
                        HStack(spacing: 2) {
                            playResultIcon(for: playResult.type)
                                .foregroundColor(.white)
                                .font(.caption2)
                            
                            Text(playResultAbbreviation(for: playResult.type))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(playResultColor(for: playResult.type))
                        .cornerRadius(4)
                        .offset(x: 4, y: -4)
                    } else {
                        // Unrecorded indicator
                        Text("?")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(Color.gray)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                    
                    // Highlight star indicator
                    if clip.isHighlight {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .frame(width: 18, height: 18)
                            .offset(x: -4, y: 4)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if let playResult = clip.playResult {
                        HStack {
                            Text(playResult.type.displayName)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            if clip.isHighlight {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                        }
                    } else {
                        Text("Unrecorded Play")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let game = clip.game, !game.opponent.isEmpty {
                        Text("vs \(game.opponent)")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    } else if let _ = clip.game {
                        Text("Game")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    } else if let practice = clip.practice {
                        if let date = practice.date {
                            Text("Practice - \(date, format: .dateTime.month().day().year())")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        } else {
                            Text("Practice")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        }
                    } else {
                        Text("Unassigned")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let createdAt = clip.createdAt {
                        Text(createdAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Recorded date unavailable")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel({
            var parts: [String] = []
            if let result = clip.playResult?.type.displayName { parts.append(result) } else { parts.append("Unrecorded Play") }
            if let game = clip.game, !game.opponent.isEmpty { parts.append("vs \(game.opponent)") }
            else if clip.practice != nil { parts.append("Practice") }
            if let createdAt = clip.createdAt { parts.append(DateFormatter.mediumDateTime.string(from: createdAt)) }
            return parts.joined(separator: ", ")
        }())
        .accessibilityHint("Opens the video")
        .contentShape(Rectangle())
        .task {
            await loadThumbnail()
        }
    }
    
    @MainActor
    private func loadThumbnail() async {
        // Skip if already loading
        guard !isLoadingThumbnail else { return }
        // Skip if we already have image
        guard thumbnailImage == nil else { return }
        
        // Check if we have a thumbnail path
        guard let thumbnailPath = clip.thumbnailPath else {
            // Generate thumbnail if none exists
            await generateMissingThumbnail()
            return
        }
        
        isLoadingThumbnail = true
        
        do {
            // Load thumbnail asynchronously
            let image = try await ThumbnailCache.shared.loadThumbnail(at: thumbnailPath)
            thumbnailImage = image
        } catch {
            print("Failed to load thumbnail: \(error)")
            // Try to regenerate thumbnail
            await generateMissingThumbnail()
        }
        
        isLoadingThumbnail = false
    }
    
    private func generateMissingThumbnail() async {
        print("Generating missing thumbnail for clip: \(clip.fileName)")
        
        let videoURL = URL(fileURLWithPath: clip.filePath)
        let result = await VideoFileManager.generateThumbnail(from: videoURL)
        
        await MainActor.run {
            switch result {
            case .success(let thumbnailPath):
                clip.thumbnailPath = thumbnailPath
                do { try modelContext.save() } catch { print("Failed to persist thumbnail path: \(error)") }
                Task {
                    await loadThumbnail()
                }
            case .failure(let error):
                print("Failed to generate thumbnail: \(error)")
                isLoadingThumbnail = false
            }
        }
    }
    
    // Helper functions for play result styling
    private func playResultIcon(for type: PlayResultType) -> Image {
        switch type {
        case .single:
            return Image(systemName: "1.circle.fill")
        case .double:
            return Image(systemName: "2.circle.fill")
        case .triple:
            return Image(systemName: "3.circle.fill")
        case .homeRun:
            return Image(systemName: "4.circle.fill")
        case .walk:
            return Image(systemName: "figure.walk")
        case .strikeout:
            return Image(systemName: "k.circle.fill")
        case .groundOut:
            return Image(systemName: "arrow.down.circle.fill")
        case .flyOut:
            return Image(systemName: "arrow.up.circle.fill")
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

// MARK: - Date Formatters for VideoClipsView
private extension DateFormatter {
    static let mediumDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Thumbnail Cache
@MainActor
class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()
    private let maxCacheSize = 50 // Maximum number of thumbnails to cache

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                ThumbnailCache.shared.clearCache()
            }
        }
        cache.countLimit = maxCacheSize
    }

    func loadThumbnail(at path: String) async throws -> UIImage {
        if let cachedImage = cache.object(forKey: path as NSString) {
            return cachedImage
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard FileManager.default.fileExists(atPath: path) else {
                    continuation.resume(throwing: ThumbnailError.fileNotFound)
                    return
                }
                guard let image = UIImage(contentsOfFile: path) else {
                    continuation.resume(throwing: ThumbnailError.invalidImage)
                    return
                }
                Task { @MainActor in
                    let resizedImage = self.resizeImage(image, to: CGSize(width: 160, height: 120))
                    self.cache.setObject(resizedImage, forKey: path as NSString)
                    continuation.resume(returning: resizedImage)
                }
            }
        }
    }

    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func removeThumbnail(at path: String) {
        cache.removeObject(forKey: path as NSString)
    }

    func clearCache() {
        cache.removeAllObjects()
    }
}

enum ThumbnailError: LocalizedError {
    case fileNotFound
    case invalidImage
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Thumbnail file not found"
        case .invalidImage:
            return "Invalid image file"
        }
    }
}

// MARK: - VideoClip Cloud Status Extension

extension VideoClip {
    var cloudStatusText: String {
        if isUploaded && isAvailableOffline { return "Available Offline" }
        if isUploaded { return "In Cloud" }
        if needsUpload { return "Ready to Upload" }
        return "Local Only"
    }
}

// MARK: - Simple Cloud Indicator

struct SimpleCloudIndicator: View {
    let clip: VideoClip
    
    var body: some View {
        HStack(spacing: 8) {
            cloudIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.cloudStatusText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .accessibilityHidden(true)
                
                if clip.isUploaded {
                    Text("Synced to cloud")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .accessibilityHidden(true)
                } else {
                    Text("Local only")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
            }
            
            Spacer()
            
            if !clip.isUploaded {
                Button("Upload") {
                    // TODO: Implement upload functionality
                    print("Upload tapped for clip: \(clip.fileName)")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cloud status: \(clip.cloudStatusText)")
    }
    
    private var cloudIcon: some View {
        Group {
            if clip.isUploaded && clip.isAvailableOffline {
                Image(systemName: "icloud.and.arrow.down.fill")
                    .foregroundColor(.green)
                    .accessibilityHidden(true)
            } else if clip.isUploaded {
                Image(systemName: "icloud.fill")
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)
            } else if clip.needsUpload {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "externaldrive.fill")
                    .foregroundColor(.gray)
                    .accessibilityHidden(true)
            }
        }
        .font(.caption)
    }
}

// MARK: - ActivityView (Share Sheet Wrapper)
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    VideoClipsView(athlete: nil)
}

// MARK: - Temporary Cloud Progress View
struct CloudProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<VideoClip> { !$0.isUploaded }, sort: \VideoClip.createdAt, order: .reverse)
    private var pendingUploads: [VideoClip]
    
    var body: some View {
        NavigationStack {
            List {
                if pendingUploads.isEmpty {
                    ContentUnavailableView(
                        "All Videos Synced",
                        systemImage: "checkmark.icloud",
                        description: Text("All your videos are backed up to the cloud.")
                    )
                } else {
                    Section("Videos Ready to Upload") {
                        ForEach(pendingUploads) { clip in
                            HStack {
                                // Thumbnail
                                AsyncImage(url: clip.thumbnailPath.map { URL(fileURLWithPath: $0) }) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 38)
                                        .clipped()
                                        .cornerRadius(6)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 50, height: 38)
                                        .cornerRadius(6)
                                        .overlay(
                                            Image(systemName: "video")
                                                .foregroundColor(.white)
                                                .font(.caption)
                                                .accessibilityHidden(true)
                                        )
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    if let playResult = clip.playResult {
                                        Text(playResult.type.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    } else {
                                        Text("Practice Clip")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    
                                    if let createdAt = clip.createdAt {
                                        Text(createdAt, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Date unavailable")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button("Upload") {
                                    // TODO: Implement upload functionality
                                    print("Upload tapped for clip: \(clip.fileName)")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    
                    Section("Bulk Actions") {
                        Button("Upload All Videos") {
                            // TODO: Implement bulk upload
                            print("Upload all videos tapped")
                        }
                        .disabled(pendingUploads.isEmpty)
                        
                        Button("Upload Highlights Only") {
                            // TODO: Implement highlights upload
                            print("Upload highlights tapped")
                        }
                        .disabled(pendingUploads.filter { $0.isHighlight }.isEmpty)
                    }
                }
            }
            .navigationTitle("Cloud Storage")
            .refreshable {
                // Refresh cloud status
            }
        }
    }
}

struct PracticePickerSheet: View {
    let athlete: Athlete
    let onPick: (Practice) -> Void
    @Environment(\.dismiss) private var dismiss

    var practices: [Practice] {
        athlete.practices.sorted { (lhs, rhs) in
            switch (lhs.date, rhs.date) {
            case let (l?, r?): return l > r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return false
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if practices.isEmpty {
                    ContentUnavailableView(
                        "No Practices",
                        systemImage: "figure.run",
                        description: Text("Create a practice to copy this clip into.")
                    )
                } else {
                    Section("Select Practice") {
                        ForEach(practices) { practice in
                            Button {
                                onPick(practice)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "figure.run")
                                    if let date = practice.date {
                                        Text(date, format: .dateTime.month().day().year().hour().minute())
                                    } else {
                                        Text("Practice")
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Copy to Practice")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

