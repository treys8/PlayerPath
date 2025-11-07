//
//  VideoRecorderView_Refactored.swift
//  PlayerPath
//
//  Created by Assistant on 10/27/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI
import CoreMedia
import UIKit

// This is the refactored version showing how to use the new components
struct VideoRecorderView_Refactored: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let athlete: Athlete?
    let game: Game?
    let practice: Practice?
    
    // Refactored: Use dedicated service objects
    @StateObject private var permissionManager = VideoRecordingPermissionManager()
    @StateObject private var uploadService = VideoUploadService()
    
    // Simplified state management
    @State private var recordedVideoURL: URL?
    @State private var showingPlayResultOverlay = false
    @State private var showingPhotoPicker = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var showingNativeCamera = false
    
    init(athlete: Athlete?, game: Game? = nil, practice: Practice? = nil) {
        self.athlete = athlete
        self.game = game
        self.practice = practice
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                mainContent
                
                loadingOverlays
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        print("VideoRecorder: Cancel button tapped")
                        cleanupAndDismiss()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showingNativeCamera) {
            NativeCameraView { videoURL in
                print("VideoRecorder: onVideoRecorded called with URL: \(videoURL)")
                recordedVideoURL = videoURL
                showingNativeCamera = false
                showingPlayResultOverlay = true
            } onCancel: {
                print("VideoRecorder: onCancel called from NativeCameraView")
                showingNativeCamera = false
            }
        }
        .sheet(isPresented: $showingPlayResultOverlay) {
            if let videoURL = recordedVideoURL {
                PlayResultOverlayView(
                    videoURL: videoURL,
                    athlete: athlete,
                    game: game,
                    practice: practice,
                    onSave: { result in
                        saveVideoWithResult(videoURL: videoURL, playResult: result)
                        dismiss()
                    },
                    onCancel: {
                        VideoFileManager.cleanup(url: videoURL)
                        recordedVideoURL = nil
                        showingPlayResultOverlay = false
                    }
                )
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedVideoItem, matching: .videos)
        .onChange(of: selectedVideoItem) { _, newItem in
            handleSelectedVideo(newItem)
        }
        .alert("Permission Required", isPresented: $permissionManager.showingPermissionAlert) {
            Button("Settings") {
                permissionManager.openSettings()
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(permissionManager.permissionAlertMessage)
        }
        .alert("Error", isPresented: $uploadService.showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(uploadService.errorMessage)
        }
    }
    
    // MARK: - View Components
    
    private var mainContent: some View {
        VStack(spacing: 25) {
            headerSection
            Spacer()
            
            // Refactored: Use dedicated options view
            VideoRecordingOptionsView(
                onRecordVideo: {
                    print("VideoRecorder: Record Video button tapped")
                    checkCameraPermission()
                },
                onUploadVideo: {
                    print("VideoRecorder: Upload Video button tapped")
                    showingPhotoPicker = true
                }
            )
            
            Spacer()
        }
        .padding()
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            if let game = game {
                HStack {
                    Text("LIVE GAME")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    
                    Spacer()
                }
                
                Text("vs \(game.opponent)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            } else if let practice = practice {
                Text("Practice Session")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(practice.date, formatter: DateFormatter.shortDate)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text("Video Recording")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }
    
    @ViewBuilder
    private var loadingOverlays: some View {
        if uploadService.isProcessingVideo {
            LoadingOverlay(message: "Processing video...")
        }
        
        if permissionManager.isRequestingPermissions {
            LoadingOverlay(message: "Requesting permissions...")
        }
    }
    
    // MARK: - Business Logic
    
    private func handleSelectedVideo(_ item: PhotosPickerItem?) {
        Task {
            let result = await uploadService.processSelectedVideo(item)
            switch result {
            case .success(let videoURL):
                recordedVideoURL = videoURL
                showingPlayResultOverlay = true
            case .failure(let error):
                print("Failed to process video: \(error)")
                // Error is already handled by uploadService
            }
        }
    }
    
    private func checkCameraPermission() {
        Task {
            let result = await permissionManager.checkPermissions()
            switch result {
            case .success:
                // Add delay to ensure permission dialogs have fully dismissed
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                showingNativeCamera = true
            case .failure(let error):
                print("Permission check failed: \(error)")
                // Error is already handled by permissionManager
            }
        }
    }
    
    private func saveVideoWithResult(videoURL: URL, playResult: PlayResultType?) {
        guard let athlete = athlete else {
            print("ERROR: No athlete selected for video save")
            return
        }
        
        print("Saving video for athlete: \(athlete.name)")
        print("Original video URL: \(videoURL)")
        
        Task {
            do {
                // Use the new VideoFileManager
                let permanentURL = try VideoFileManager.copyToDocuments(from: videoURL)
                
                // Create video clip
                let videoClip = VideoClip(
                    fileName: permanentURL.lastPathComponent,
                    filePath: permanentURL.path
                )
                
                print("Created VideoClip - fileName: \(videoClip.fileName), filePath: \(videoClip.filePath)")
                
                // Generate thumbnail asynchronously using the new VideoFileManager
                Task {
                    let thumbnailResult = await VideoFileManager.generateThumbnail(from: permanentURL)
                    await MainActor.run {
                        switch thumbnailResult {
                        case .success(let thumbnailPath):
                            videoClip.thumbnailPath = thumbnailPath
                            print("Generated thumbnail for video: \(thumbnailPath)")
                            
                            // Save the updated model with thumbnail
                            do {
                                try self.modelContext.save()
                            } catch {
                                print("Failed to save thumbnail path: \(error)")
                            }
                        case .failure(let error):
                            print("Failed to generate thumbnail: \(error)")
                        }
                    }
                }
                
                // Create play result if provided
                if let playResult = playResult {
                    let result = PlayResult(type: playResult)
                    videoClip.playResult = result
                    modelContext.insert(result)
                    
                    // Mark as highlight if it's a hit
                    videoClip.isHighlight = playResult.isHighlight
                    
                    // Update statistics
                    if let statistics = athlete.statistics {
                        statistics.addPlayResult(playResult)
                        print("Updated statistics for play result: \(playResult.rawValue)")
                    } else {
                        print("Warning: No statistics object found for athlete")
                    }
                }
                
                // Link to game or practice
                if let game = game {
                    videoClip.game = game
                    game.videoClips.append(videoClip)
                    print("Linked video to game: \(game.opponent)")
                } else if let practice = practice {
                    videoClip.practice = practice
                    practice.videoClips.append(videoClip)
                    print("Linked video to practice")
                } else {
                    print("Video not linked to game or practice")
                }
                
                videoClip.athlete = athlete
                athlete.videoClips.append(videoClip)
                
                modelContext.insert(videoClip)
                try modelContext.save()
                
                print("Successfully saved video clip to SwiftData")
                
                // Clean up temporary file if it exists
                if videoURL != permanentURL {
                    VideoFileManager.cleanup(url: videoURL)
                }
                
            } catch {
                print("Failed to save video: \(error)")
                print("Error details: \(error.localizedDescription)")
            }
        }
    }
    
    private func cleanupAndDismiss() {
        print("VideoRecorder: cleanupAndDismiss called")
        
        // Clean up any temporary files
        if let videoURL = recordedVideoURL {
            VideoFileManager.cleanup(url: videoURL)
        }
        
        // Reset all state
        showingPlayResultOverlay = false
        recordedVideoURL = nil
        showingNativeCamera = false
        showingPhotoPicker = false
        selectedVideoItem = nil
        
        print("VideoRecorder: State reset, attempting dismiss")
        dismiss()
    }
}

// MARK: - Supporting Views

struct LoadingOverlay: View {
    let message: String
    
    var body: some View {
        Color.black.opacity(0.7)
            .ignoresSafeArea()
        
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            
            Text(message)
                .font(.headline)
                .foregroundColor(.white)
        }
    }
}

#Preview {
    VideoRecorderView_Refactored(athlete: nil)
}