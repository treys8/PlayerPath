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
import os

private let cameraLog = Logger(subsystem: "com.playerpath.app", category: "Camera")

@MainActor
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

    nonisolated(unsafe) let captureSession = AVCaptureSession()
    nonisolated(unsafe) private var videoDevice: AVCaptureDevice?
    nonisolated(unsafe) private var audioDevice: AVCaptureDevice?
    nonisolated(unsafe) private var videoInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var audioInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var movieFileOutput: AVCaptureMovieFileOutput?

    nonisolated(unsafe) private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var pulseTimer: Timer?
    private var sessionQueue = DispatchQueue(label: "com.playerpath.camera")
    private var orientationObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var interruptionEndObserver: NSObjectProtocol?
    private var hasShownTimeWarning = false
    @MainActor private var stoppingRecording = false
    @MainActor @Published var currentOrientation: UIDeviceOrientation = .portrait

    var minZoom: CGFloat = 1.0
    var maxZoom: CGFloat = 10.0
    private var zoomGestureBase: CGFloat = 1.0  // Zoom captured at gesture start
    private var focusTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    @MainActor private var hasStartedSession = false

    // MARK: - Constants

    private nonisolated enum Constants {
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
        // Begin session setup immediately — overlaps with fullScreenCover animation
        startupTask = Task { [weak self] in
            await self?.startSession()
        }
    }

    deinit {
        startupTask?.cancel()
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = interruptionEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        // Stop capture session on session queue (async to avoid deadlock
        // if deinit is called from the session queue itself)
        let session = captureSession
        sessionQueue.async {
            session.stopRunning()
        }
        recordingTimer?.invalidate()
        pulseTimer?.invalidate()
    }

    // MARK: - Orientation

    @MainActor
    private func startOrientationMonitoring() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        currentOrientation = UIDevice.current.orientation.isValidInterfaceOrientation
            ? UIDevice.current.orientation : .portrait

        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let orientation = UIDevice.current.orientation
                guard orientation.isValidInterfaceOrientation else { return }
                self.currentOrientation = orientation
            }
        }
    }

    private func stopOrientationMonitoring() {
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
            orientationObserver = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    /// Updates an AVCaptureConnection's orientation to match the given device orientation.
    nonisolated private func updateConnectionOrientation(_ connection: AVCaptureConnection, for orientation: UIDeviceOrientation? = nil) {
        let deviceOrientation = orientation ?? .portrait

        if #available(iOS 17.0, *) {
            let angle: CGFloat = switch deviceOrientation {
            case .landscapeLeft: 0       // Home button on right → natural landscape
            case .landscapeRight: 180    // Home button on left
            case .portraitUpsideDown: 270
            default: 90                  // Portrait (default)
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else {
            let videoOrientation: AVCaptureVideoOrientation = switch deviceOrientation {
            case .landscapeLeft: .landscapeRight   // Inverted mapping (camera vs device)
            case .landscapeRight: .landscapeLeft
            case .portraitUpsideDown: .portraitUpsideDown
            default: .portrait
            }
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = videoOrientation
            }
        }
    }

    // MARK: - Session Management

    @MainActor
    func startSession() async {
        guard !hasStartedSession else { return }
        hasStartedSession = true

        await checkPermissions()

        // Reset zoom baseline for fresh session
        zoomGestureBase = 1.0

        // Start monitoring orientation
        startOrientationMonitoring()

        // Capture all settings values before crossing the actor boundary
        let qualityPreset = settings.quality.avPreset
        let targetFrameRate = settings.frameRate.fps
        let audioEnabled = settings.audioEnabled
        let stabilizationMode = settings.stabilizationMode.avMode
        let videoCodec = settings.format.codec

        // Observe session interruptions (phone calls, etc.)
        setupInterruptionObservers()

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()

            // Set session preset based on quality
            if self.captureSession.canSetSessionPreset(qualityPreset) {
                self.captureSession.sessionPreset = qualityPreset
            }

            self.setupCamera(targetFrameRate: targetFrameRate)
            self.setupAudio(audioEnabled: audioEnabled)
            self.setupOutput(stabilizationMode: stabilizationMode, codec: videoCodec)

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()

            Task { @MainActor [weak self] in
                self?.isSessionReady = true
            }
        }
    }

    /// Re-applies current settings to the running capture session (e.g. after settings sheet dismisses).
    @MainActor
    func reconfigureSession() {
        guard hasStartedSession, !isRecording else { return }

        let qualityPreset = settings.quality.avPreset
        let targetFrameRate = settings.frameRate.fps
        let audioEnabled = settings.audioEnabled
        let stabilizationMode = settings.stabilizationMode.avMode
        let videoCodec = settings.format.codec

        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.captureSession.beginConfiguration()

            if self.captureSession.canSetSessionPreset(qualityPreset) {
                self.captureSession.sessionPreset = qualityPreset
            }

            self.setupCamera(targetFrameRate: targetFrameRate)
            self.setupAudio(audioEnabled: audioEnabled)
            self.setupOutput(stabilizationMode: stabilizationMode, codec: videoCodec)

            self.captureSession.commitConfiguration()
        }
    }

    @MainActor
    func stopSession() {
        startupTask?.cancel()
        startupTask = nil

        if isRecording {
            stopRecording()
        }

        stopOrientationMonitoring()
        removeInterruptionObservers()

        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }

        isSessionReady = false
        hasStartedSession = false
    }

    // MARK: - Session Interruption Handling

    @MainActor
    private func setupInterruptionObservers() {
        removeInterruptionObservers()

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: captureSession,
            queue: .main
        ) { [weak self] notification in
            // Extract value from notification before crossing concurrency boundary
            _ = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int)
                .flatMap { AVCaptureSession.InterruptionReason(rawValue: $0) }
            Task { @MainActor [weak self] in
                guard let self else { return }

                // If recording, stop gracefully — the delegate will receive the file
                if self.isRecording {
                    self.stopRecording()
                    self.handleError("Recording stopped — camera was interrupted", isFatal: false)
                }
            }
        }

        interruptionEndObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: captureSession,
            queue: .main
        ) { _ in
        }
    }

    private func removeInterruptionObservers() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = interruptionEndObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionEndObserver = nil
        }
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

    nonisolated private func setupCamera(targetFrameRate: Int) {
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

            // Pick highest-resolution format that supports the target frame rate
            let matchingFormats = camera.formats.filter { format in
                format.videoSupportedFrameRateRanges.contains(where: { range in
                    range.minFrameRate <= Double(targetFrameRate) &&
                    range.maxFrameRate >= Double(targetFrameRate)
                })
            }
            if let bestFormat = matchingFormats.max(by: { a, b in
                let aDims = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
                let bDims = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
                return Int(aDims.width) * Int(aDims.height) < Int(bDims.width) * Int(bDims.height)
            }) {
                camera.activeFormat = bestFormat
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

                // Update zoom limits, clamping to actual device range
                let deviceMinZoom = camera.minAvailableVideoZoomFactor
                let deviceMaxZoom = camera.maxAvailableVideoZoomFactor
                Task { @MainActor in
                    self.minZoom = deviceMinZoom
                    self.maxZoom = min(deviceMaxZoom, 10.0)
                    self.currentZoom = max(Constants.defaultZoom, deviceMinZoom)
                }
            }
        } catch {
            Task { @MainActor in
                self.handleError("Failed to setup camera: \(error.localizedDescription)", isFatal: true)
            }
        }
    }

    nonisolated private func setupAudio(audioEnabled: Bool) {
        // Always remove existing audio input first so toggling OFF actually takes effect
        if let existingInput = audioInput {
            captureSession.removeInput(existingInput)
            audioInput = nil
        }

        guard audioEnabled else { return }

        // Get microphone
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
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
            Task { @MainActor in
                self.handleError("Microphone unavailable — video will record without audio.", isFatal: false)
            }
        }
    }

    nonisolated private func setupOutput(stabilizationMode: AVCaptureVideoStabilizationMode, codec: AVVideoCodecType = .hevc) {
        // Remove existing output
        if let existingOutput = movieFileOutput {
            captureSession.removeOutput(existingOutput)
        }

        let output = AVCaptureMovieFileOutput()

        // Set maximum duration
        output.maxRecordedDuration = CMTime(seconds: Constants.maxRecordingDuration, preferredTimescale: 600)

        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            movieFileOutput = output
        }

        // Configure after adding to session so connections are available
        if let connection = output.connection(with: .video) {
            // Set video codec (HEVC or H.264)
            if output.availableVideoCodecTypes.contains(codec) {
                output.setOutputSettings([AVVideoCodecKey: codec], for: connection)
            }

            // Set stabilization
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = stabilizationMode
            }

            // Set orientation based on current device orientation
            updateConnectionOrientation(connection)
        }
    }

    // MARK: - Recording Control

    @MainActor
    func startRecording() {
        guard !isRecording, !stoppingRecording, let output = movieFileOutput else { return }

        // Set immediately to prevent double-tap race condition —
        // the delegate callback that normally sets this fires asynchronously
        isRecording = true

        // Check storage
        guard hasEnoughStorage() else {
            isRecording = false
            handleError("Not enough storage space available", isFatal: false)
            return
        }

        // Generate output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        // Lock orientation for this recording
        let orientation = currentOrientation

        // Start recording with correct orientation
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Update connection orientation right before recording starts
            if let connection = output.connection(with: .video) {
                self.updateConnectionOrientation(connection, for: orientation)
            }
            output.startRecording(to: outputURL, recordingDelegate: self)
        }
    }

    @MainActor
    func stopRecording() {
        guard isRecording, !stoppingRecording, let output = movieFileOutput else { return }

        stoppingRecording = true

        sessionQueue.async {
            output.stopRecording()
        }

        // Haptic feedback
        Haptics.medium()
    }

    /// Single place to reset all recording state — called only from delegate callbacks.
    @MainActor
    private func cleanupRecordingState() {
        isRecording = false
        stoppingRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        pulseTimer?.invalidate()
        pulseTimer = nil
        recordingTimeString = "0:00"
        recordingPulse = false
    }

    @MainActor
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startTime = self.recordingStartTime else { return }

                let elapsed = Date().timeIntervalSince(startTime)
                let minutes = Int(elapsed) / 60
                let seconds = Int(elapsed) % 60

                self.recordingTimeString = String(format: "%d:%02d", minutes, seconds)

                // Warning at 9 minutes (fire once)
                if elapsed >= Constants.warningDuration && !self.hasShownTimeWarning {
                    self.hasShownTimeWarning = true
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

        let minimumRequired: Int64 = StorageConstants.bytesPerGB
        return freeSize > minimumRequired
    }

    // MARK: - Camera Controls

    @MainActor
    func flipCamera() {
        guard !isRecording else { return }

        currentCameraPosition = currentCameraPosition == .back ? .front : .back
        zoomGestureBase = 1.0

        let targetFrameRate = settings.frameRate.fps

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()
            self.setupCamera(targetFrameRate: targetFrameRate)
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

        // Apply as torch mode — flash mode is for photos; torch controls the LED during video
        let torchMode: AVCaptureDevice.TorchMode = {
            switch flashMode {
            case .on: return .on
            case .auto: return .auto
            default: return .off
            }
        }()

        guard let device = videoDevice else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.hasTorch && device.isTorchAvailable {
                    device.torchMode = torchMode
                }
                device.unlockForConfiguration()
            } catch {
                cameraLog.warning("Failed to configure torch: \(error.localizedDescription)")
            }
        }

        Haptics.light()
    }

    @MainActor
    func handleZoom(scale: CGFloat) {
        // scale is cumulative from gesture start (1.0 = no change), so use zoomGestureBase
        let newZoom = min(max(zoomGestureBase * scale, minZoom), maxZoom)
        setZoom(newZoom)
    }

    @MainActor
    func endZoomGesture() {
        zoomGestureBase = currentZoom
    }

    @MainActor
    func setZoom(_ zoom: CGFloat) {
        guard let device = videoDevice else { return }

        currentZoom = zoom

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = zoom
                device.unlockForConfiguration()
            } catch {
                cameraLog.warning("Failed to set zoom factor: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func handleTapToFocus(at point: CGPoint, viewSize: CGSize) {
        guard let device = videoDevice else { return }

        // Convert tap point to device coordinates (0-1 range), accounting for orientation
        let devicePoint: CGPoint
        switch currentOrientation {
        case .landscapeRight:
            devicePoint = CGPoint(
                x: point.x / viewSize.width,
                y: point.y / viewSize.height
            )
        case .landscapeLeft:
            devicePoint = CGPoint(
                x: 1.0 - (point.x / viewSize.width),
                y: 1.0 - (point.y / viewSize.height)
            )
        default: // Portrait
            devicePoint = CGPoint(
                x: point.y / viewSize.height,
                y: 1.0 - (point.x / viewSize.width)
            )
        }

        // Show focus reticle — cancel previous dismiss task so it doesn't clear the new point
        lastFocusPoint = point
        focusTask?.cancel()
        focusTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                self.lastFocusPoint = nil
            }
        }

        Haptics.light()

        // Perform device configuration off main thread
        sessionQueue.async {
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
            } catch {
                cameraLog.warning("Failed to set focus/exposure point: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Error Handling

    @MainActor
    private func handleError(_ message: String, isFatal: Bool) {
        currentError = message
        self.isFatalError = isFatal
        showingError = true


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
        Task { @MainActor in
            // If stop was already requested before delegate fired, don't re-enable recording
            guard !self.stoppingRecording else { return }
            self.isRecording = true
            self.recordingStartTime = Date()
            self.hasShownTimeWarning = false
            self.startRecordingTimer()
            self.startPulseTimer()
            Haptics.success()
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error = error {
            // AVFoundation reports some "errors" (e.g. hitting max duration/file size)
            // that still produce valid, complete video files. Don't delete those.
            let nsError = error as NSError
            let isRecoverable = nsError.domain == AVFoundationErrorDomain
                && [AVError.maximumDurationReached.rawValue,
                    AVError.maximumFileSizeReached.rawValue].contains(nsError.code)
            if isRecoverable,
               FileManager.default.fileExists(atPath: outputFileURL.path) {
                // File is valid despite the "error" — fall through to success path
            } else {
                // Genuine failure — delete the partial temp file
                try? FileManager.default.removeItem(at: outputFileURL)
                Task { @MainActor in
                    self.cleanupRecordingState()
                    self.handleError("Recording failed: \(error.localizedDescription)", isFatal: false)
                }
                return
            }
        }


        // Verify file exists
        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            Task { @MainActor in
                self.cleanupRecordingState()
                self.handleError("Recording file not found", isFatal: false)
            }
            return
        }

        // Return the URL to SwiftUI
        Task { @MainActor in
            self.cleanupRecordingState()
            self.recordedVideoURL = outputFileURL
        }
    }
}

