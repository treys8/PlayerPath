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

struct VideoRecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
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
                    // Header info
                    VStack(spacing: 10) {
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
                                print("VideoRecorder: Record Video button tapped")
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
                                        Text("Use device camera")
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
                            .accessibilityLabel("Record new video using device camera")
                            .accessibilityHint("Opens camera to record a new video")
                            
                            // Upload from library
                            Button(action: { 
                                print("VideoRecorder: Upload Video button tapped")
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
                                        Text("Choose from library")
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
                            .accessibilityLabel("Upload video from photo library")
                            .accessibilityHint("Opens photo library to select an existing video")
                        }
                    }
                    
                    // Large dismiss button at bottom
                    Button(action: {
                        print("VideoRecorder: Large dismiss button tapped")
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
                        print("VideoRecorder: Cancel button tapped")
                        cleanupAndDismiss()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        print("VideoRecorder: Done button tapped")
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
                // Just dismiss the camera if user cancels
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
                        // Delete the temporary video
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
        // Basic file existence and size check
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Video file not found."
            showingErrorAlert = true
            return false
        }
        
        // Check file size (limit to 500MB)
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
        
        // Use async validation for duration in the background
        Task {
            await validateVideoDurationAsync(at: url)
        }
        
        return true
    }
    
    @MainActor
    private func validateVideoDurationAsync(at url: URL) async {
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            // Check if video is too long (more than 10 minutes)
            if durationSeconds > 600 {
                errorMessage = "Video is too long. Please select a video under 10 minutes."
                showingErrorAlert = true
            }
            
            // Check if video is too short (less than 1 second)  
            if durationSeconds < 1 {
                errorMessage = "Video is too short. Please select a video at least 1 second long."
                showingErrorAlert = true
            }
        } catch {
            print("Warning: Could not validate video duration: \(error)")
        }
    }
    
    private func saveVideoWithResult(videoURL: URL, playResult: PlayResultType?) {
        guard let athlete = athlete else { 
            print("ERROR: No athlete selected for video save")
            return 
        }
        
        print("Saving video for athlete: \(athlete.name)")
        
        // Create a permanent location for the video
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
            
            print("Successfully saved video clip")
            
            // Clean up temporary file if it exists
            if videoURL != permanentURL {
                try? FileManager.default.removeItem(at: videoURL)
            }
            
        } catch {
            print("Failed to save video: \(error)")
        }
    }
    
    private func cleanupAndDismiss() {
        print("VideoRecorder: cleanupAndDismiss called")
        
        // Clean up any temporary files
        if let videoURL = recordedVideoURL {
            try? FileManager.default.removeItem(at: videoURL)
            print("VideoRecorder: Cleaned up temp video file")
        }
        
        // Reset all state
        showingPlayResultOverlay = false
        recordedVideoURL = nil
        showingNativeCamera = false
        showingPhotoPicker = false
        selectedVideoItem = nil
        
        print("VideoRecorder: State reset, attempting dismiss")
        
        // Dismiss the view
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

// MARK: - Native Camera View
struct NativeCameraView: UIViewControllerRepresentable {
    let onVideoRecorded: (URL) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 300 // 5 minutes max
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: NativeCameraView
        
        init(_ parent: NativeCameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let videoURL = info[.mediaURL] as? URL {
                parent.onVideoRecorded(videoURL)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            parent.onCancel()
        }
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

// MARK: - Video Transferable for PhotosPicker
struct VideoTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let copy = documentsPath.appendingPathComponent("imported_\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(url: copy)
        }
    }
}