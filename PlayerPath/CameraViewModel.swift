//
//  CameraViewModel.swift
//  PlayerPath
//
//  Created by Assistant on 12/25/25.
//  ViewModel for modern camera with AVFoundation control
//

import SwiftUI
@preconcurrency import AVFoundation
import Combine

class CameraViewModel: NSObject, ObservableObject {

    // MARK: - Published Properties

    @MainActor @Published var isSessionReady = false
    @MainActor @Published var isRecording = false
    @MainActor @Published var currentZoom: CGFloat = 1.0
    @MainActor @Published var showGrid = false
    @MainActor @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @MainActor @Published var lastFocusPoint: CGPoint?
    @MainActor @Published var recordingTimeString = "0:00"
    @MainActor @Published var recordingPulse = false
    @MainActor @Published var showingError = false
    @MainActor @Published var currentError: String?
    @MainActor @Published var isFatalError = false
    @MainActor @Published var recordedVideoURL: URL?
    @MainActor @Published var settings: VideoRecordingSettings

    // MARK: - AVFoundation Properties

    let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private var audioDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?

    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var pulseTimer: Timer?
    private var sessionQueue = DispatchQueue(label: "com.playerpath.camera")

    var minZoom: CGFloat = 1.0
    var maxZoom: CGFloat = 10.0

    // MARK: - Constants

    private enum Constants {
        static let maxRecordingDuration: TimeInterval = 600 // 10 minutes
        static let warningDuration: TimeInterval = 540 // 9 minutes
        static let defaultZoom: CGFloat = 1.0
        static let zoomVelocityFactor: CGFloat = 0.1
        static let focusAnimationDuration: TimeInterval = 0.3
    }

    // MARK: - Initialization

    @MainActor
    init(settings: VideoRecordingSettings? = nil) {
        self.settings = settings ?? VideoRecordingSettings.shared
        super.init()
    }

    deinit {
        // Stop capture session on session queue (non-isolated context)
        sessionQueue.sync {
            captureSession.stopRunning()
        }
        recordingTimer?.invalidate()
        pulseTimer?.invalidate()
    }

    // MARK: - Session Management

    @MainActor
    func startSession() async {
        await checkPermissions()

        // Capture settings value before async boundary
        let qualityPreset = settings.quality.avPreset

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()

            // Set session preset based on quality
            if self.captureSession.canSetSessionPreset(qualityPreset) {
                self.captureSession.sessionPreset = qualityPreset
            }

            self.setupCamera()
            self.setupAudio()
            self.setupOutput()

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()

            Task { @MainActor [weak self] in
                self?.isSessionReady = true
            }
        }
    }

    @MainActor
    func stopSession() {
        if isRecording {
            stopRecording()
        }

        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }

        isSessionReady = false
    }

    @MainActor
    private func checkPermissions() async {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        if cameraStatus != .authorized {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                handleError("Camera access denied", isFatal: true)
                return
            }
        }

        if settings.audioEnabled && audioStatus != .authorized {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                handleError("Microphone access denied. Video will record without audio.", isFatal: false)
            }
        }
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        // Remove existing video input
        if let existingInput = videoInput {
            captureSession.removeInput(existingInput)
        }

        // Get camera device
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: currentCameraPosition
        ) else {
            Task { @MainActor in
                self.handleError("Camera not available", isFatal: true)
            }
            return
        }

        videoDevice = camera

        // Configure camera
        do {
            try camera.lockForConfiguration()

            // Set frame rate if supported
            let targetFrameRate = settings.frameRate.fps
            if let formatSupported = camera.formats.first(where: { format in
                format.videoSupportedFrameRateRanges.contains(where: { range in
                    range.minFrameRate <= Double(targetFrameRate) &&
                    range.maxFrameRate >= Double(targetFrameRate)
                })
            }) {
                camera.activeFormat = formatSupported
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
            }

            // Set focus and exposure modes
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }

            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }

            // Set white balance
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            // Configure stabilization
            camera.unlockForConfiguration()

            // Add camera input
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                videoInput = input

                // Update zoom limits
                Task { @MainActor in
                    self.minZoom = camera.minAvailableVideoZoomFactor
                    self.maxZoom = min(camera.maxAvailableVideoZoomFactor, 10.0)
                    self.currentZoom = Constants.defaultZoom
                }
            }
        } catch {
            Task { @MainActor in
                self.handleError("Failed to setup camera: \(error.localizedDescription)", isFatal: true)
            }
        }
    }

    private func setupAudio() {
        guard settings.audioEnabled else { return }

        // Remove existing audio input
        if let existingInput = audioInput {
            captureSession.removeInput(existingInput)
        }

        // Get microphone
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            print("⚠️ Microphone not available")
            return
        }

        audioDevice = microphone

        do {
            let input = try AVCaptureDeviceInput(device: microphone)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                audioInput = input
            }
        } catch {
            print("⚠️ Failed to setup audio: \(error.localizedDescription)")
        }
    }

    private func setupOutput() {
        // Remove existing output
        if let existingOutput = movieFileOutput {
            captureSession.removeOutput(existingOutput)
        }

        let output = AVCaptureMovieFileOutput()

        // Set maximum duration
        output.maxRecordedDuration = CMTime(seconds: Constants.maxRecordingDuration, preferredTimescale: 600)

        // Configure video codec
        if let connection = output.connection(with: .video) {
            // Set stabilization
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = settings.stabilizationMode.avMode
            }

            // Set orientation
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(0) {
                    connection.videoRotationAngle = 0
                }
            } else {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        }

        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            movieFileOutput = output
        }
    }

    // MARK: - Recording Control

    @MainActor
    func startRecording() {
        guard !isRecording, let output = movieFileOutput else { return }

        // Check storage
        guard hasEnoughStorage() else {
            handleError("Not enough storage space available", isFatal: false)
            return
        }

        // Generate output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        // Start recording
        sessionQueue.async {
            output.startRecording(to: outputURL, recordingDelegate: self)
        }

        // Update UI
        isRecording = true
        recordingStartTime = Date()

        // Start timers
        startRecordingTimer()
        startPulseTimer()

        // Haptic feedback
        Haptics.success()
    }

    @MainActor
    func stopRecording() {
        guard isRecording, let output = movieFileOutput else { return }

        sessionQueue.async {
            output.stopRecording()
        }

        // Update UI
        isRecording = false
        recordingTimer?.invalidate()
        pulseTimer?.invalidate()

        // Haptic feedback
        Haptics.medium()
    }

    @MainActor
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let startTime = self.recordingStartTime else { return }

                let elapsed = Date().timeIntervalSince(startTime)
                let minutes = Int(elapsed) / 60
                let seconds = Int(elapsed) % 60

                self.recordingTimeString = String(format: "%d:%02d", minutes, seconds)

                // Warning at 9 minutes
                if elapsed >= Constants.warningDuration && elapsed < Constants.warningDuration + 1 {
                    Haptics.warning()
                }
            }
        }
    }

    @MainActor
    private func startPulseTimer() {
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordingPulse.toggle()
            }
        }
    }

    private func hasEnoughStorage() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSize = attributes[.systemFreeSize] as? Int64 else {
            return true // Assume enough if we can't check
        }

        let minimumRequired: Int64 = 1_000_000_000 // 1GB minimum
        return freeSize > minimumRequired
    }

    // MARK: - Camera Controls

    @MainActor
    func flipCamera() {
        currentCameraPosition = currentCameraPosition == .back ? .front : .back

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()
            self.setupCamera()
            self.captureSession.commitConfiguration()
        }

        Haptics.medium()
    }

    @MainActor
    func toggleFlash() {
        switch flashMode {
        case .off:
            flashMode = .on
        case .on:
            flashMode = .auto
        case .auto:
            flashMode = .off
        @unknown default:
            flashMode = .off
        }

        Haptics.light()
    }

    @MainActor
    func handleZoom(scale: CGFloat) {
        let newZoom = min(max(currentZoom * scale, minZoom), maxZoom)
        setZoom(newZoom)
    }

    @MainActor
    func setZoom(_ zoom: CGFloat) {
        guard let device = videoDevice else { return }

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = zoom
            device.unlockForConfiguration()

            currentZoom = zoom
        } catch {
            print("⚠️ Failed to set zoom: \(error.localizedDescription)")
        }
    }

    @MainActor
    func handleTapToFocus(at point: CGPoint) {
        guard let device = videoDevice else { return }

        // Convert tap point to device coordinates (0-1 range)
        // Note: This assumes portrait orientation. In production, you'd convert based on preview layer bounds
        // and handle all orientations properly
        let screenBounds = UIScreen.main.bounds
        let devicePoint = CGPoint(
            x: point.y / screenBounds.height,
            y: 1.0 - (point.x / screenBounds.width)
        )

        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()

            // Show focus reticle
            lastFocusPoint = point

            // Hide after animation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.lastFocusPoint = nil
            }

            Haptics.light()
        } catch {
            print("⚠️ Failed to set focus: \(error.localizedDescription)")
        }
    }

    // MARK: - Error Handling

    @MainActor
    private func handleError(_ message: String, isFatal: Bool) {
        currentError = message
        self.isFatalError = isFatal
        showingError = true

        print("🔴 Camera Error: \(message)")

        if isFatal {
            stopSession()
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraViewModel: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        print("✅ Recording started: \(fileURL)")
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error = error {
            print("🔴 Recording error: \(error.localizedDescription)")
            Task { @MainActor in
                self.handleError("Recording failed: \(error.localizedDescription)", isFatal: false)
            }
            return
        }

        print("✅ Recording completed: \(outputFileURL)")

        // Verify file exists
        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            Task { @MainActor in
                self.handleError("Recording file not found", isFatal: false)
            }
            return
        }

        // Return the URL to SwiftUI
        Task { @MainActor in
            self.recordedVideoURL = outputFileURL
        }
    }
}

