//
//  VideoRecorderViewUnified.swift
//  PlayerPath
//
//  Updated video recorder view using the new unified systems
//

import SwiftUI
import PhotosUI
import AVFoundation

struct VideoRecorderViewUnified: View {
    // MARK: - State Management
    @StateObject private var videoManager = VideoManager()
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var processedVideoClip: VideoClip?
    
    // MARK: - Configuration
    @State private var selectedQuality: VideoQuality = .medium
    @State private var autoUpload = true
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    actionButtonsSection
                    
                    settingsSection
                    
                    if !videoManager.processingVideos.isEmpty {
                        processingSection
                    }
                    
                    if !videoManager.uploadProgress.isEmpty {
                        uploadProgressSection
                    }
                    
                    if processedVideoClip != nil {
                        videoPreviewSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Record Video")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Clear All Progress") {
                            clearAllProgress()
                        }
                        .disabled(videoManager.processingVideos.isEmpty && videoManager.uploadProgress.isEmpty)
                        
                        Button("Test Error Handling") {
                            testErrorHandling()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedVideoItem,
            matching: .videos,
            photoLibrary: .shared()
        )
        .onChange(of: selectedVideoItem) { _, newValue in
            if let item = newValue {
                handleVideoSelection(item)
            }
        }
        .errorHandling(videoManager.errorHandler) // Apply unified error handling
    }
    
    // MARK: - View Sections
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .padding(.bottom, 8)
            
            Text("Record or Import Video")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Capture your athletic performance or choose from your library")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            // Record Video Button
            Button(action: recordVideo) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "video.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Record Video")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("Use device camera")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.red.gradient)
                )
            }
            .accessibilityLabel("Record new video using device camera")
            .accessibilityHint("Opens camera to record a new video")
            
            // Upload Video Button
            Button(action: { showingPhotoPicker = true }) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Import Video")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("Choose from library")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.blue.gradient)
                )
            }
            .accessibilityLabel("Import video from photo library")
            .accessibilityHint("Opens photo library to select an existing video")
        }
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                // Video Quality Setting
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video Quality")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Video Quality", selection: $selectedQuality) {
                        ForEach(VideoQuality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Auto Upload Toggle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto Upload")
                            .font(.subheadline)
                        Text("Automatically upload to cloud after processing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("Auto Upload", isOn: $autoUpload)
                        .labelsHidden()
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
    
    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing Videos")
                .font(.headline)
                .padding(.horizontal)
            
            ForEach(Array(videoManager.processingVideos), id: \.self) { videoId in
                ProcessingVideoRow(
                    videoId: videoId,
                    compressionProgress: videoManager.compressionProgress[videoId] ?? 0.0
                )
            }
        }
    }
    
    private var uploadProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Uploading Videos")
                .font(.headline)
                .padding(.horizontal)
            
            ForEach(Array(videoManager.uploadProgress.keys), id: \.self) { videoId in
                UploadProgressRow(
                    videoId: videoId,
                    progress: videoManager.uploadProgress[videoId] ?? 0.0
                )
            }
        }
    }
    
    private var videoPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processed Video")
                .font(.headline)
                .padding(.horizontal)
            
            if let videoClip = processedVideoClip {
                VideoClipPreview(videoClip: videoClip) {
                    uploadProcessedVideo(videoClip)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func recordVideo() {
        Task {
            let result = await videoManager.recordVideo()
            
            switch result {
            case .success(let videoClip):
                processedVideoClip = videoClip
                
                if autoUpload {
                    await uploadProcessedVideo(videoClip)
                }
                
            case .failure:
                // Error is automatically handled by videoManager.errorHandler
                break
            }
        }
    }
    
    private func handleVideoSelection(_ item: PhotosPickerItem) {
        Task {
            let result = await videoManager.importVideo(item)
            
            switch result {
            case .success(let videoClip):
                processedVideoClip = videoClip
                
                if autoUpload {
                    await uploadProcessedVideo(videoClip)
                }
                
            case .failure:
                // Error is automatically handled by videoManager.errorHandler
                break
            }
        }
    }
    
    private func uploadProcessedVideo(_ videoClip: VideoClip) async {
        let result = await videoManager.uploadVideo(videoClip, quality: selectedQuality)
        
        switch result {
        case .success(let cloudURL):
            print("Video uploaded successfully to: \(cloudURL)")
            // Could show success message or update UI
            
        case .failure:
            // Error is automatically handled by videoManager.errorHandler
            break
        }
    }
    
    private func clearAllProgress() {
        videoManager.uploadProgress.removeAll()
        videoManager.compressionProgress.removeAll()
        // Note: Can't directly modify processingVideos as it's managed by VideoManager
    }
    
    private func testErrorHandling() {
        // Demonstrate different error scenarios
        let testErrors = [
            PlayerPathError.networkUnavailable,
            PlayerPathError.videoFileTooLarge(size: 200_000_000, maxSize: 100_000_000),
            PlayerPathError.unsupportedVideoFormat(format: "avi"),
            PlayerPathError.cameraPermissionDenied
        ]
        
        let randomError = testErrors.randomElement()!
        videoManager.errorHandler.handle(randomError, context: "Error handling test")
    }
}

// MARK: - Supporting Views

struct ProcessingVideoRow: View {
    let videoId: UUID
    let compressionProgress: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gear")
                    .foregroundColor(.orange)
                Text("Processing video...")
                    .font(.subheadline)
                Spacer()
                Text("\(Int(compressionProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: compressionProgress)
                .tint(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct UploadProgressRow: View {
    let videoId: UUID
    let progress: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.blue)
                Text("Uploading to cloud...")
                    .font(.subheadline)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: progress)
                .tint(.blue)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct VideoClipPreview: View {
    let videoClip: VideoClip
    let onUpload: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Video processed successfully")
                    .font(.subheadline)
                    .foregroundColor(.green)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("File: \(videoClip.fileName)")
                    .font(.caption)
                Text("Duration: \(videoClip.duration, specifier: "%.1f") seconds")
                    .font(.caption)
                if let resolution = videoClip.resolution {
                    Text("Resolution: \(resolution)")
                        .font(.caption)
                }
                Text("Size: \(ByteCountFormatter.string(fromByteCount: Int64(videoClip.fileSize), countStyle: .file))")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            
            Button("Upload to Cloud", action: onUpload)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

#Preview {
    VideoRecorderViewUnified()
}