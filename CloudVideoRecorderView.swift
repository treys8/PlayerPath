//
//  CloudVideoRecorderView.swift
//  PlayerPath
//
//  Enhanced video recorder with cloud upload capability
//

import SwiftUI
import SwiftData

struct CloudVideoRecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cloudManager = VideoCloudManager()
    
    let athlete: Athlete?
    let game: Game?
    let practice: Practice?
    
    @State private var isRecording = false
    @State private var showingPlayResultOverlay = false
    @State private var recordedVideoURL: URL?
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var showingPhotoPicker = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var showingNativeCamera = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var isProcessingVideo = false
    
    init(athlete: Athlete?, game: Game? = nil, practice: Practice? = nil) {
        self.athlete = athlete
        self.game = game
        self.practice = practice
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 40) {
                    // Header info with cloud sync status
                    VStack(spacing: 10) {
                        HStack {
                            if let game = game {
                                VStack(alignment: .leading) {
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
                                }
                            } else if let practice = practice {
                                VStack(alignment: .leading) {
                                    Text("Practice Session")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    
                                    Text(practice.date, formatter: DateFormatter.shortDate)
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            } else {
                                Text("Video Recording")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            // Cloud sync indicator
                            VStack {
                                Image(systemName: "icloud")
                                    .foregroundColor(.white)
                                Text("Auto-Sync")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Recording options
                    VStack(spacing: 30) {
                        Text("Choose Recording Option")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        VStack(spacing: 20) {
                            // Use device camera
                            Button(action: { 
                                checkCameraPermission()
                            }) {
                                HStack(spacing: 15) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Record Video")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                        Text("Use device camera • Auto-uploads to cloud")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(Color.red.opacity(0.8))
                                )
                            }
                            
                            // Upload from library
                            Button(action: { 
                                showingPhotoPicker = true 
                            }) {
                                HStack(spacing: 15) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Upload Video")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                        Text("Choose from library • Syncs across devices")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(Color.blue.opacity(0.8))
                                )
                            }
                        }
                    }
                    
                    // Upload progress indicator
                    if !cloudManager.uploadProgress.isEmpty {
                        VStack(spacing: 10) {
                            Text("Uploading videos...")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            
                            ForEach(Array(cloudManager.uploadProgress.keys), id: \.self) { videoID in
                                if let progress = cloudManager.uploadProgress[videoID] {
                                    ProgressView(value: progress)
                                        .progressViewStyle(LinearProgressViewStyle(tint: .green))
                                        .frame(height: 4)
                                }
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Large dismiss button at bottom
                    Button(action: {
                        cleanupAndDismiss()
                    }) {
                        Text("Close Video Recorder")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.8))
                            .cornerRadius(12)
                    }
                    
                    Spacer()
                }
                .padding()
                
                // Loading overlay
                if isProcessingVideo {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                        
                        Text("Processing video...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        cleanupAndDismiss()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
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
                recordedVideoURL = videoURL
                showingPlayResultOverlay = true
            } onCancel: {
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
                        try? FileManager.default.removeItem(at: videoURL)
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
        .alert("Permission Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(permissionAlertMessage)
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Video Handling Methods
    
    private func handleSelectedVideo(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        isProcessingVideo = true
        
        Task {
            do {
                if let video = try await item.loadTransferable(type: VideoTransferable.self) {
                    if validateVideo(at: video.url) {
                        await MainActor.run {
                            recordedVideoURL = video.url
                            showingPlayResultOverlay = true
                            isProcessingVideo = false
                        }
                    } else {
                        await MainActor.run {
                            isProcessingVideo = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load video: \(error.localizedDescription)"
                    showingErrorAlert = true
                    isProcessingVideo = false
                }
            }
        }
    }
    
    private func validateVideo(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Video file not found."
            showingErrorAlert = true
            return false
        }
        
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
            let maxSize: Int64 = 500 * 1024 * 1024 // 500MB
            if fileSize > maxSize {
                errorMessage = "Video file is too large. Please select a video under 500MB."
                showingErrorAlert = true
                return false
            }
            
            if fileSize < 1024 { // Less than 1KB
                errorMessage = "Video file appears to be invalid or corrupted."
                showingErrorAlert = true
                return false
            }
        }
        
        return true
    }
    
    private func saveVideoWithResult(videoURL: URL, playResult: PlayResultType?) {
        guard let athlete = athlete else { 
            print("ERROR: No athlete selected for video save")
            return 
        }
        
        print("Saving video for athlete: \(athlete.name)")
        
        // Create a permanent location for the video locally
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let permanentURL = documentsPath.appendingPathComponent("\(UUID().uuidString).mov")
        
        do {
            try FileManager.default.copyItem(at: videoURL, to: permanentURL)
            
            // Create video clip
            let videoClip = VideoClip(
                fileName: permanentURL.lastPathComponent,
                filePath: permanentURL.path
            )
            
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
            }
            
            videoClip.athlete = athlete
            athlete.videoClips.append(videoClip)
            
            modelContext.insert(videoClip)
            try modelContext.save()
            
            print("Successfully saved video clip locally")
            
            // Upload to cloud asynchronously
            Task {
                do {
                    let cloudURL = try await cloudManager.uploadVideo(videoClip, athlete: athlete)
                    print("Successfully uploaded video to cloud: \(cloudURL)")
                } catch {
                    print("Failed to upload video to cloud: \(error)")
                    // Video is still saved locally, user can try to sync later
                }
            }
            
            // Clean up temporary file if it exists
            if videoURL != permanentURL {
                try? FileManager.default.removeItem(at: videoURL)
            }
            
        } catch {
            print("Failed to save video: \(error)")
            errorMessage = "Failed to save video: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
    
    private func cleanupAndDismiss() {
        // Clean up any temporary files
        if let videoURL = recordedVideoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }
        
        // Reset all state
        showingPlayResultOverlay = false
        recordedVideoURL = nil
        showingNativeCamera = false
        showingPhotoPicker = false
        selectedVideoItem = nil
        
        dismiss()
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingNativeCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.showingNativeCamera = true
                    } else {
                        self.showPermissionAlert(message: "Camera access is required to record videos. Please enable camera access in Settings.")
                    }
                }
            }
        case .denied, .restricted:
            showPermissionAlert(message: "Camera access is required to record videos. Please enable camera access in Settings.")
        @unknown default:
            showPermissionAlert(message: "Camera access is required to record videos.")
        }
    }
    
    private func showPermissionAlert(message: String) {
        permissionAlertMessage = message
        showingPermissionAlert = true
    }
}

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
}