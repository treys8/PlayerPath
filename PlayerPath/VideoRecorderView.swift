//
//  VideoRecorderView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI
import CoreMedia
import UIKit
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.app", category: "VideoRecorderView")

@available(*, deprecated, message: "Use VideoRecorderView_Refactored as the canonical recorder UI.")
struct VideoRecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?
    let game: Game?
    let practice: Practice?
    
    @State private var isRecording = false {
        didSet { print("VideoRecorder: isRecording changed to \(isRecording)") }
    }
    @State private var showingPlayResultOverlay = false {
        didSet { print("VideoRecorder: showingPlayResultOverlay changed to \(showingPlayResultOverlay)") }
    }
    @State private var recordedVideoURL: URL? {
        didSet { 
            if let url = recordedVideoURL {
                print("VideoRecorder: recordedVideoURL set to \(url)")
            } else {
                print("VideoRecorder: recordedVideoURL set to nil")
            }
        }
    }
    @State private var showingPermissionAlert = false {
        didSet { print("VideoRecorder: showingPermissionAlert changed to \(showingPermissionAlert)") }
    }
    @State private var permissionAlertMessage = ""
    @State private var showingPhotoPicker = false {
        didSet { print("VideoRecorder: showingPhotoPicker changed to \(showingPhotoPicker)") }
    }
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var showingNativeCamera = false {
        didSet { print("VideoRecorder: showingNativeCamera changed to \(showingNativeCamera)") }
    }
    @State private var showingErrorAlert = false {
        didSet { print("VideoRecorder: showingErrorAlert changed to \(showingErrorAlert)") }
    }
    @State private var errorMessage = ""
    @State private var isProcessingVideo = false {
        didSet { print("VideoRecorder: isProcessingVideo changed to \(isProcessingVideo)") }
    }
    @State private var isRequestingPermissions = false {
        didSet { print("VideoRecorder: isRequestingPermissions changed to \(isRequestingPermissions)") }
    }
    @State private var selectedVideoQuality: UIImagePickerController.QualityType = .typeHigh
    @State private var showingQualityPicker = false
    @State private var showingLowStorageAlert = false
    
    init(athlete: Athlete?, game: Game? = nil, practice: Practice? = nil) {
        self.athlete = athlete
        self.game = game
        self.practice = practice
    }
    
    private var navigationTitleText: String {
        if let game = game { return "Record: vs \(game.opponent)" }
        if practice != nil { return "Record: Practice" }
        return "Record Video"
    }

    private func hapticTap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    
    // MARK: - View Components
    
    var body: some View {
        navigationContent
            .fullScreenCover(isPresented: $showingNativeCamera, onDismiss: cameraDismissed, content: cameraView)
            .sheet(isPresented: $showingPlayResultOverlay, content: playResultSheet)
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedVideoItem, matching: .videos)
            .onChange(of: selectedVideoItem) { _, newItem in
                handleSelectedVideo(newItem)
            }
            .onChange(of: showingPlayResultOverlay) { _, newValue in
                if newValue {
                    UIAccessibility.post(notification: .announcement, argument: "Play result options")
                }
            }
            .alert("Permission Required", isPresented: $showingPermissionAlert, actions: permissionAlertActions, message: permissionAlertContent)
            .alert("Error", isPresented: $showingErrorAlert, actions: errorAlertActions, message: errorAlertContent)
            .alert("Low Storage Space", isPresented: $showingLowStorageAlert, actions: lowStorageAlertActions, message: lowStorageAlertContent)
    }
    
    // MARK: - Body Subviews
    
    private var navigationContent: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                mainContent
                loadingOverlays
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    cancelButton
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .confirmationDialog("Video Quality", isPresented: $showingQualityPicker, titleVisibility: .visible, actions: qualityPickerActions, message: qualityPickerMessage)
        }
    }
    
    private var cancelButton: some View {
        Button("Cancel") {
            logger.info("Cancel button tapped")
            cleanupAndDismiss()
            hapticTap(.light)
        }
        .foregroundColor(.white)
        .fontWeight(.semibold)
        .accessibilityLabel("Cancel recording")
        .accessibilityHint("Dismiss and discard current recording flow")
    }
    
    @ViewBuilder
    private func qualityPickerActions() -> some View {
        Button("High Quality (Recommended)") {
            selectedVideoQuality = .typeHigh
            hapticTap(.light)
        }
        Button("Medium Quality") {
            selectedVideoQuality = .typeMedium
            hapticTap(.light)
        }
        Button("Low Quality (Smaller file)") {
            selectedVideoQuality = .typeLow
            hapticTap(.light)
        }
        Button("Cancel", role: .cancel) {
            hapticTap(.light)
        }
    }
    
    private func qualityPickerMessage() -> some View {
        Text("Choose video quality. Higher quality produces larger files.")
    }
    
    private func cameraDismissed() {
        print("VideoRecorder: fullScreenCover onDismiss called")
    }
    
    private func cameraView() -> some View {
        logger.info("Creating UIImagePickerController")
        return NativeCameraView(videoQuality: selectedVideoQuality) { videoURL in
            logger.info("onVideoRecorded called with URL: \(videoURL)")
            hapticTap()
            recordedVideoURL = videoURL
            showingNativeCamera = false
            showingPlayResultOverlay = true
        } onCancel: {
            logger.info("onCancel called from NativeCameraView")
            hapticTap(.light)
            showingNativeCamera = false
        }
        .accessibilityLabel("Camera")
        .accessibilityHint("Record a new video")
    }
    
    @ViewBuilder
    private func playResultSheet() -> some View {
        if let videoURL = recordedVideoURL {
            PlayResultOverlayView(
                videoURL: videoURL,
                athlete: athlete,
                game: game,
                practice: practice,
                onSave: { result in
                    hapticTap()
                    saveVideoWithResult(videoURL: videoURL, playResult: result)
                    dismiss()
                },
                onCancel: {
                    hapticTap(.light)
                    // Delete the temporary video
                    try? FileManager.default.removeItem(at: videoURL)
                    recordedVideoURL = nil
                    showingPlayResultOverlay = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
        }
    }
    
    @ViewBuilder
    private func permissionAlertActions() -> some View {
        Button("Settings") {
            CameraPermissionManager.openSettings()
        }
        .accessibilityHint("Open Settings to grant permissions")
        
        Button("Cancel", role: .cancel) {
            dismiss()
        }
        .accessibilityHint("Close and return to the previous screen")
    }
    
    private func permissionAlertContent() -> some View {
        Text(permissionAlertMessage)
    }
    
    @ViewBuilder
    private func errorAlertActions() -> some View {
        Button("OK", role: .cancel) { }
            .accessibilityHint("Dismiss error")
    }
    
    private func errorAlertContent() -> some View {
        Text(errorMessage)
    }
    
    @ViewBuilder
    private func lowStorageAlertActions() -> some View {
        Button("Continue Anyway", role: .none) {
            // Proceed with recording despite low storage
            showingPhotoPicker = false
            selectedVideoItem = nil
            showingNativeCamera = true
        }
        Button("Cancel", role: .cancel) { }
    }
    
    private func lowStorageAlertContent() -> some View {
        Text(StorageManager.getLowStorageMessage())
    }
    
    private var mainContent: some View {
        VStack(spacing: 25) {
            headerSection
            Spacer()
            recordingOptionsSection
            Spacer()
        }
        .padding()
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            if let game = game {
                HStack {
                    Text("LIVE GAME")
                        .font(.caption).bold()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(.thinMaterial)
                        )
                        .overlay(
                            Capsule().stroke(Color.red.opacity(0.6), lineWidth: 1)
                        )
                        .foregroundStyle(.red)
                    
                    Spacer()
                }
                
                Text("vs \(game.opponent)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("Opponent: \(game.opponent)")
            } else if let practice = practice {
                Text("Practice Session")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("Practice session")
                
                if let date = practice.date {
                    Text(date, style: .date)
                        .accessibilityLabel("Date: \(date.formatted(date: .abbreviated, time: .omitted))")
                } else {
                    Text("Date TBA")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            } else {
                Text("Video Recording")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .contentTransition(.opacity)
    }
    
    private var recordingOptionsSection: some View {
        VStack(spacing: 20) {
            Text("Choose Recording Option")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Choose recording option")

            VideoRecordingOptionsView(
                onRecordVideo: {
                    hapticTap()
                    checkCameraPermission()
                },
                onUploadVideo: {
                    hapticTap(.light)
                    showingPhotoPicker = true
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recording options")
            .accessibilityHint("Record a new video or upload from your library")

            // Video Quality Selector
            qualitySelector

            helpfulTip
        }
    }
    
    private var qualitySelector: some View {
        Button {
            hapticTap(.light)
            showingQualityPicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "video.badge.waveform")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Video Quality")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    Text(qualityText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .accessibilityLabel("Video quality: \(qualityText)")
        .accessibilityHint("Tap to change video recording quality")
    }
    
    private var qualityText: String {
        switch selectedVideoQuality {
        case .typeHigh:
            return "High Quality"
        case .typeMedium:
            return "Medium Quality"
        case .typeLow:
            return "Low Quality"
        case .type640x480:
            return "640x480"
        case .typeIFrame1280x720:
            return "720p"
        case .typeIFrame960x540:
            return "540p"
        @unknown default:
            return "High Quality"
        }
    }

    private var helpfulTip: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                
                Text("Tip: Position camera to capture the full swing and follow-through")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
                    )
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tip: Position camera to capture the full swing and follow-through")
            
            // Storage indicator
            StorageIndicatorView()
        }
    }
    
    @ViewBuilder
    private var loadingOverlays: some View {
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
            .transition(.opacity)
            .animation(.snappy, value: isProcessingVideo)
            .accessibilityAddTraits(.isModal)
            .accessibilityLabel("Processing video")
            .accessibilityHint("Please wait while the selected video is processed")
        }
        
        if isRequestingPermissions {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
                
                Text("Requesting permissions...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .transition(.opacity)
            .animation(.snappy, value: isRequestingPermissions)
            .accessibilityAddTraits(.isModal)
            .accessibilityLabel("Requesting permissions")
            .accessibilityHint("Please allow camera and microphone access")
        }
    }
    
    private func handleSelectedVideo(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        isProcessingVideo = true
        
        Task {
            do {
                if let video = try await item.loadTransferable(type: VideoTransferable.self) {
                    let validationResult = await VideoFileManager.validateVideo(at: video.url)
                    await MainActor.run {
                        switch validationResult {
                        case .success:
                            recordedVideoURL = video.url
                            showingPlayResultOverlay = true
                        case .failure(let error):
                            errorMessage = error.localizedDescription
                            showingErrorAlert = true
                        }
                        isProcessingVideo = false
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Failed to load the selected video"
                        showingErrorAlert = true
                        isProcessingVideo = false
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
    
    private func saveVideoWithResult(videoURL: URL, playResult: PlayResultType?) {
        guard let athlete = athlete else { 
            print("ERROR: No athlete selected for video save")
            return 
        }
        
        print("Saving video for athlete: \(athlete.name)")
        print("Original video URL: \(videoURL)")
        
        do {
            // Use VideoFileManager to copy to permanent location
            let permanentURL = try VideoFileManager.copyToDocuments(from: videoURL)
            print("Permanent video URL: \(permanentURL)")
            
            // Create video clip
            let videoClip = VideoClip(
                fileName: permanentURL.lastPathComponent,
                filePath: permanentURL.path
            )
            
            print("Created VideoClip - fileName: \(videoClip.fileName), filePath: \(videoClip.filePath)")
            
            // Generate thumbnail asynchronously
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
                        print("Failed to generate thumbnail for video: \(error.localizedDescription)")
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
                
                // Update athlete's overall statistics (create if missing)
                if athlete.statistics == nil {
                    let stats = AthleteStatistics()
                    stats.athlete = athlete
                    athlete.statistics = stats
                    modelContext.insert(stats)
                    print("Created new Statistics for athlete \(athlete.name)")
                }
                if let statistics = athlete.statistics {
                    statistics.addPlayResult(playResult)
                    print("Updated athlete overall statistics for play result: \(playResult.rawValue)")
                }
                
                // Update individual game statistics if this is linked to a game (create if missing)
                if let game = game {
                    if game.gameStats == nil {
                        let gs = GameStatistics()
                        gs.game = game
                        game.gameStats = gs
                        modelContext.insert(gs)
                        print("Created new GameStatistics for game vs \(game.opponent)")
                    }
                    if let gameStats = game.gameStats {
                        gameStats.addPlayResult(playResult)
                        print("Updated game statistics for play result: \(playResult.rawValue)")
                        print("Game stats now: \(gameStats.hits) hits in \(gameStats.atBats) at bats")
                    }
                }
                
                // Broadcast to update other parts of the app (e.g., dashboard, stats tab)
                let hitTypeString: String
                switch playResult {
                case .single: hitTypeString = "single"
                case .double: hitTypeString = "double"
                case .triple: hitTypeString = "triple"
                case .homeRun: hitTypeString = "homeRun"
                default: hitTypeString = String(playResult.rawValue)
                }
                NotificationCenter.default.post(name: .recordedHitResult, object: ["hitType": hitTypeString])
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
            
            logger.info("Successfully saved video clip to SwiftData")
            
            // Ensure any stats creations/updates are persisted
            do { try modelContext.save() } catch { print("Failed to save stats changes: \(error)") }
            
            // Clean up temporary file if it exists
            if videoURL != permanentURL {
                VideoFileManager.cleanup(url: videoURL)
                print("Cleaned up temporary video file")
            }
            
        } catch {
            logger.error("Failed to save video: \(String(describing: error))")
            print("Error details: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func cleanupAndDismiss() {
        print("VideoRecorder: cleanupAndDismiss called")
        
        // Clean up any temporary files
        if let videoURL = recordedVideoURL {
            VideoFileManager.cleanup(url: videoURL)
            print("VideoRecorder: Cleaned up temp video file")
        }
        
        // Reset all state
        showingPlayResultOverlay = false
        recordedVideoURL = nil
        showingNativeCamera = false
        showingPhotoPicker = false
        selectedVideoItem = nil
        isRequestingPermissions = false
        isProcessingVideo = false
        
        logger.info("State reset, attempting dismiss")
        
        // Dismiss the view
        dismiss()
    }
    
    private func checkCameraPermission() {
        logger.info("Checking camera and microphone permissions…")
        
        let cameraStatus = CameraPermissionManager.cameraStatus()
        let microphoneStatus = CameraPermissionManager.microphoneStatus()
        
        // If both permissions are already granted, check storage before proceeding
        if case .authorized = cameraStatus, case .authorized = microphoneStatus {
            print("VideoRecorder: Both permissions authorized, checking storage")
            
            // Check storage before opening camera
            if StorageManager.shouldWarnAboutLowStorage() {
                showingLowStorageAlert = true
                return
            }
            
            print("VideoRecorder: Storage OK, preparing to show native camera")
            // Ensure Photos picker is not presenting
            showingPhotoPicker = false
            selectedVideoItem = nil
            // Present camera
            showingNativeCamera = true
            return
        }
        
        // If any permission is denied, show alert
        if case .denied(let message) = cameraStatus {
            showPermissionAlert(message: message)
            return
        }
        
        if case .restricted(let message) = cameraStatus {
            showPermissionAlert(message: message)
            return
        }
        
        if case .denied(let message) = microphoneStatus {
            showPermissionAlert(message: message)
            return
        }
        
        if case .restricted(let message) = microphoneStatus {
            showPermissionAlert(message: message)
            return
        }
        
        // Request permissions that are not determined
        requestBothPermissions()
    }
    
    private func requestBothPermissions() {
        logger.info("Requesting both camera and microphone permissions…")
        
        isRequestingPermissions = true
        
        Task {
            let result = await CameraPermissionManager.checkAndRequestAllPermissions()
            
            await MainActor.run {
                isRequestingPermissions = false
                
                switch result {
                case .success:
                    logger.info("All permissions granted, checking storage before showing camera")
                    
                    // Check storage before proceeding
                    if StorageManager.shouldWarnAboutLowStorage() {
                        self.showingLowStorageAlert = true
                        return
                    }
                    
                    logger.info("Storage OK, showing camera with delay")
                    // Add delay to ensure permission dialogs have fully dismissed
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        logger.info("Preparing to present camera: resetting Photos picker state")
                        // Ensure Photos picker is not presenting
                        self.showingPhotoPicker = false
                        self.selectedVideoItem = nil
                        logger.info("Actually setting showingNativeCamera = true")
                        self.showingNativeCamera = true
                    }
                    
                case .failure(let message):
                    self.showPermissionAlert(message: message)
                }
            }
        }
    }
    
    @MainActor
    private func showPermissionAlert(message: String) {
        permissionAlertMessage = message
        showingPermissionAlert = true
    }
}

// MARK: - Camera Preview View
struct CameraPreviewView: UIViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var recordedVideoURL: URL?
    @Binding var showingPlayResultOverlay: Bool
    
    func makeUIView(context: Context) -> CameraPreview {
        let preview = CameraPreview()
        preview.delegate = context.coordinator
        return preview
    }
    
    func updateUIView(_ uiView: CameraPreview, context: Context) {
        if isRecording && !uiView.isRecording {
            uiView.startRecording()
        } else if !isRecording && uiView.isRecording {
            uiView.stopRecording()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CameraPreviewDelegate {
        let parent: CameraPreviewView
        
        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }
        
        func didFinishRecording(at url: URL) {
            DispatchQueue.main.async {
                self.parent.recordedVideoURL = url
                self.parent.showingPlayResultOverlay = true
                self.parent.isRecording = false
            }
        }
        
        func didFailWithError(_ error: Error) {
            DispatchQueue.main.async {
                self.parent.isRecording = false
                print("Recording failed: \(error)")
            }
        }
    }
}

// MARK: - Camera Preview UIView
protocol CameraPreviewDelegate: AnyObject {
    func didFinishRecording(at url: URL)
    func didFailWithError(_ error: Error)
}

class CameraPreview: UIView {
    weak var delegate: CameraPreviewDelegate?
    private var captureSession: AVCaptureSession!
    private var videoOutput: AVCaptureMovieFileOutput!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private(set) var isRecording = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        captureSession?.stopRunning()
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else {
            return
        }
        
        captureSession.addInput(videoInput)
        
        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }
        
        videoOutput = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mov")
        
        videoOutput.startRecording(to: outputURL, recordingDelegate: self)
        isRecording = true
    }
    
    func stopRecording() {
        guard isRecording else { return }
        videoOutput.stopRecording()
    }
}

extension CameraPreview: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        isRecording = false
        
        if let error = error {
            delegate?.didFailWithError(error)
        } else {
            delegate?.didFinishRecording(at: outputFileURL)
        }
    }
}

// MARK: - Storage Indicator View
struct StorageIndicatorView: View {
    @State private var storageInfo: StorageInfo?
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: storageIcon)
                .font(.system(size: 14))
                .foregroundColor(storageColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Available: \(availableSpaceText)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
                
                if let info = storageInfo, info.estimatedMinutesOfVideo > 0 {
                    Text("~\(info.estimatedMinutesOfVideo) min of video")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Storage gauge
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 3)
                    .frame(width: 30, height: 30)
                
                Circle()
                    .trim(from: 0, to: storagePercentage)
                    .stroke(storageColor, lineWidth: 3)
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(storagePercentage * 100))")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(storageColor.opacity(0.3), lineWidth: 1)
                )
        )
        .onAppear {
            refreshStorage()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Storage available: \(availableSpaceText), approximately \(storageInfo?.estimatedMinutesOfVideo ?? 0) minutes of video")
    }
    
    private var availableSpaceText: String {
        storageInfo?.formattedAvailableSpace ?? "Calculating..."
    }
    
    private var storagePercentage: Double {
        storageInfo?.percentageAvailable ?? 0
    }
    
    private var storageIcon: String {
        guard let info = storageInfo else {
            return "internaldrive"
        }
        
        switch info.storageLevel {
        case .good:
            return "internaldrive"
        case .moderate:
            return "internaldrive.fill"
        case .low, .critical:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var storageColor: Color {
        guard let info = storageInfo else {
            return .gray
        }
        
        switch info.storageLevel {
        case .good:
            return .green
        case .moderate:
            return .orange
        case .low:
            return .red
        case .critical:
            return .red
        }
    }
    
    private func refreshStorage() {
        storageInfo = StorageManager.getStorageInfo()
    }
}

