//
//  VideoEditorView.swift
//  PlayerPath
//
//  Created by Assistant on 10/31/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import AVKit

struct VideoEditorView: View {
    let clip: VideoClip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var editor = VideoEditor()
    @State private var player: AVPlayer?
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var showingExportSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Video Player Area
                if let player = player {
                    VideoPlayerWithTrimOverlay(
                        player: player,
                        editor: editor,
                        duration: editor.videoDuration
                    )
                    .frame(height: 300)
                    .background(Color.black)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 300)
                        .overlay(
                            ProgressView("Loading video...")
                                .foregroundColor(.white)
                        )
                }
                
                // Trim Controls
                VStack(spacing: 20) {
                    // Timeline Scrubber
                    TimelineScrubber(
                        startTime: $editor.startTime,
                        endTime: $editor.endTime,
                        currentTime: $editor.currentTime,
                        duration: editor.videoDuration,
                        player: player
                    )
                    .frame(height: 80)
                    .padding(.horizontal)
                    
                    // Time Display
                    HStack {
                        VStack {
                            Text("Start")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatTime(editor.startTime))
                                .font(.headline)
                                .monospaced()
                        }
                        
                        Spacer()
                        
                        VStack {
                            Text("Duration")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatTime(editor.endTime - editor.startTime))
                                .font(.headline)
                                .monospaced()
                        }
                        
                        Spacer()
                        
                        VStack {
                            Text("End")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatTime(editor.endTime))
                                .font(.headline)
                                .monospaced()
                        }
                    }
                    .padding(.horizontal)
                    
                    // Control Buttons
                    HStack(spacing: 20) {
                        Button("Reset") {
                            editor.resetTrim()
                            updatePlayerTime()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Preview Trim") {
                            previewTrimmedSection()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Spacer()
                        
                        Button("Save Trimmed") {
                            Task {
                                await exportTrimmedVideo()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isExporting || !editor.hasTrimChanges)
                    }
                    .padding(.horizontal)
                    
                    // Export Progress
                    if isExporting {
                        VStack(spacing: 10) {
                            ProgressView("Exporting video...", value: exportProgress, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle())
                            
                            Text("\(Int(exportProgress * 100))% complete")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
                .background(Color(.systemBackground))
                
                Spacer()
            }
            .navigationTitle("Edit Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Export as New Clip") {
                            Task {
                                await exportTrimmedVideo(asNewClip: true)
                            }
                        }
                        
                        Button("Replace Original") {
                            Task {
                                await exportTrimmedVideo(asNewClip: false)
                            }
                        }
                        .disabled(!editor.hasTrimChanges)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(isExporting)
                }
            }
        }
        .task {
            await setupEditor()
        }
        .alert("Export Successful", isPresented: $showingExportSuccess) {
            Button("Done") {
                dismiss()
            }
        } message: {
            Text("Your trimmed video has been saved successfully!")
        }
        .alert("Export Failed", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func setupEditor() async {
        let videoURL = URL(fileURLWithPath: clip.filePath)
        editor.setClip(clip)
        await editor.setupEditor(with: videoURL)
        
        await MainActor.run {
            player = AVPlayer(url: videoURL)
            updatePlayerTime()
        }
    }
    
    private func updatePlayerTime() {
        player?.seek(to: CMTime(seconds: editor.currentTime, preferredTimescale: 600))
    }
    
    private func previewTrimmedSection() {
        player?.seek(to: CMTime(seconds: editor.startTime, preferredTimescale: 600))
        player?.play()
        
        // Stop at end time
        DispatchQueue.main.asyncAfter(deadline: .now() + (editor.endTime - editor.startTime)) {
            player?.pause()
        }
    }
    
    private func exportTrimmedVideo(asNewClip: Bool = true) async {
        isExporting = true
        exportProgress = 0.0
        
        do {
            let outputURL = VideoFileManager.createPermanentVideoURL()
            
            // Export with progress tracking
            let success = await editor.exportTrimmedVideo(
                to: outputURL,
                progressHandler: { progress in
                    Task { @MainActor in
                        exportProgress = progress
                    }
                }
            )
            
            if success {
                // Generate thumbnail for the new video
                let thumbnailResult = await VideoFileManager.generateThumbnail(from: outputURL)
                
                if asNewClip {
                    // Create new video clip
                    await createNewVideoClip(videoURL: outputURL, thumbnailResult: thumbnailResult)
                } else {
                    // Replace original clip
                    await replaceOriginalClip(videoURL: outputURL, thumbnailResult: thumbnailResult)
                }
                
                showingExportSuccess = true
            } else {
                throw NSError(domain: "VideoEditor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        
        isExporting = false
    }
    
    @MainActor
    private func createNewVideoClip(videoURL: URL, thumbnailResult: Result<String, Error>) {
        let newClip = VideoClip(
            fileName: videoURL.lastPathComponent,
            filePath: videoURL.path
        )
        
        // Copy properties from original clip
        newClip.athlete = clip.athlete
        newClip.game = clip.game
        newClip.practice = clip.practice
        newClip.playResult = clip.playResult
        newClip.isHighlight = clip.isHighlight
        
        // Set thumbnail if generated successfully
        if case .success(let thumbnailPath) = thumbnailResult {
            newClip.thumbnailPath = thumbnailPath
        }
        
        // Add to athlete's video clips
        if let athlete = clip.athlete {
            athlete.videoClips.append(newClip)
        }
        
        modelContext.insert(newClip)
        
        do {
            try modelContext.save()
            print("Created new trimmed video clip")
        } catch {
            print("Failed to save new video clip: \(error)")
        }
    }
    
    @MainActor
    private func replaceOriginalClip(videoURL: URL, thumbnailResult: Result<String, Error>) {
        // Delete old files
        if FileManager.default.fileExists(atPath: clip.filePath) {
            try? FileManager.default.removeItem(atPath: clip.filePath)
        }
        
        if let oldThumbnail = clip.thumbnailPath {
            try? FileManager.default.removeItem(atPath: oldThumbnail)
            ThumbnailCache.shared.removeThumbnail(at: oldThumbnail)
        }
        
        // Update clip with new files
        clip.filePath = videoURL.path
        clip.fileName = videoURL.lastPathComponent
        
        if case .success(let thumbnailPath) = thumbnailResult {
            clip.thumbnailPath = thumbnailPath
        }
        
        do {
            try modelContext.save()
            print("Replaced original video clip with trimmed version")
        } catch {
            print("Failed to update video clip: \(error)")
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, milliseconds)
    }
}

// MARK: - Video Player with Trim Overlay

struct VideoPlayerWithTrimOverlay: View {
    let player: AVPlayer
    let editor: VideoEditor
    let duration: Double
    
    var body: some View {
        ZStack {
            VideoPlayer(player: player)
            
            // Trim overlay indicators
            VStack {
                Spacer()
                
                HStack {
                    // Start indicator
                    if editor.startTime > 0 {
                        VStack {
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: 4)
                            
                            Text("START")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4)
                        }
                        .opacity(0.8)
                    }
                    
                    Spacer()
                    
                    // End indicator
                    if editor.endTime < duration {
                        VStack {
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 4)
                            
                            Text("END")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4)
                        }
                        .opacity(0.8)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Timeline Scrubber

struct TimelineScrubber: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    @Binding var currentTime: Double
    let duration: Double
    let player: AVPlayer?
    
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingCurrent = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Timeline track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    // Selected region
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(
                            width: max(0, (endTime - startTime) / duration * geometry.size.width),
                            height: 8
                        )
                        .offset(x: startTime / duration * geometry.size.width)
                        .cornerRadius(4)
                    
                    // Start handle
                    Circle()
                        .fill(Color.green)
                        .frame(width: 20, height: 20)
                        .offset(x: startTime / duration * geometry.size.width - 10)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDraggingStart = true
                                    let newTime = max(0, min(endTime - 0.1, value.location.x / geometry.size.width * duration))
                                    startTime = newTime
                                    currentTime = newTime
                                    player?.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
                                }
                                .onEnded { _ in
                                    isDraggingStart = false
                                }
                        )
                    
                    // End handle
                    Circle()
                        .fill(Color.red)
                        .frame(width: 20, height: 20)
                        .offset(x: endTime / duration * geometry.size.width - 10)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDraggingEnd = true
                                    let newTime = max(startTime + 0.1, min(duration, value.location.x / geometry.size.width * duration))
                                    endTime = newTime
                                    currentTime = newTime
                                    player?.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
                                }
                                .onEnded { _ in
                                    isDraggingEnd = false
                                }
                        )
                    
                    // Current time indicator
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 24)
                        .offset(x: currentTime / duration * geometry.size.width - 1, y: -8)
                        .shadow(color: .black, radius: 1)
                }
            }
            .frame(height: 24)
            
            // Time labels
            HStack {
                Text("0:00")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Video Editor Logic

@MainActor
class VideoEditor: ObservableObject {
    @Published var startTime: Double = 0.0
    @Published var endTime: Double = 0.0
    @Published var currentTime: Double = 0.0
    @Published var videoDuration: Double = 0.0
    
    private var originalStartTime: Double = 0.0
    private var originalEndTime: Double = 0.0
    private var clip: VideoClip?
    
    var hasTrimChanges: Bool {
        return startTime != originalStartTime || endTime != originalEndTime
    }
    
    func setupEditor(with url: URL) async {
        let asset = AVURLAsset(url: url)
        
        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            videoDuration = durationSeconds
            startTime = 0.0
            endTime = durationSeconds
            currentTime = 0.0
            
            originalStartTime = 0.0
            originalEndTime = durationSeconds
            
            print("VideoEditor: Setup complete - Duration: \(durationSeconds)s")
        } catch {
            print("VideoEditor: Failed to load video duration: \(error)")
        }
    }
    
    func setClip(_ clip: VideoClip) {
        self.clip = clip
    }
    
    func resetTrim() {
        startTime = originalStartTime
        endTime = originalEndTime
        currentTime = startTime
    }
    
    func exportTrimmedVideo(to outputURL: URL, progressHandler: @escaping (Double) -> Void) async -> Bool {
        guard let clip = self.clip else { return false }
        
        // Get the source video URL from the clip
        let sourceURL = URL(fileURLWithPath: clip.filePath)
        let asset = AVURLAsset(url: sourceURL)
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            print("VideoEditor: Failed to create export session")
            return false
        }
        
        // Set time range for trim
        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
        let endCMTime = CMTime(seconds: endTime, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startCMTime, end: endCMTime)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.timeRange = timeRange
        
        // Start export with progress monitoring
        return await withCheckedContinuation { continuation in
            // Monitor progress
            let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    progressHandler(Double(exportSession.progress))
                }
            }
            
            exportSession.exportAsynchronously {
                Task { @MainActor in
                    progressTimer.invalidate()
                    
                    switch exportSession.status {
                    case .completed:
                        print("VideoEditor: Export completed successfully")
                        progressHandler(1.0)
                        continuation.resume(returning: true)
                    case .failed:
                        print("VideoEditor: Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
                        continuation.resume(returning: false)
                    case .cancelled:
                        print("VideoEditor: Export cancelled")
                        continuation.resume(returning: false)
                    default:
                        print("VideoEditor: Export finished with status: \(exportSession.status.rawValue)")
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }
}