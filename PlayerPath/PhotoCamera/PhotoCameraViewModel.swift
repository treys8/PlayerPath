//
//  PhotoCameraViewModel.swift
//  PlayerPath
//
//  AVFoundation-backed photo capture, completely separate from the video
//  recorder in `CameraViewModel` / `ModernCameraView`. Owns its own capture
//  session, photo output, and rotation coordinator — nothing is shared.
//

import SwiftUI
@preconcurrency import AVFoundation
import Combine
import os

private let photoLog = Logger(subsystem: "com.playerpath.app", category: "PhotoCamera")

@MainActor
class PhotoCameraViewModel: NSObject, ObservableObject {

    // MARK: Published State

    @Published var isSessionReady = false
    @Published var isCapturing = false
    @Published var capturedImage: UIImage?

    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    @Published var cameraPosition: AVCaptureDevice.Position = .back

    @Published var currentZoom: CGFloat = 1.0
    @Published var minZoom: CGFloat = 1.0
    @Published var maxZoom: CGFloat = 10.0

    @Published var lastFocusPoint: CGPoint?

    @Published var showGrid: Bool = false

    @Published var showingError = false
    @Published var currentError: String?
    @Published var errorNeedsSettings = false
    @Published var isFatalError = false

    // MARK: AV Plumbing

    /// Threading contract for the `nonisolated(unsafe)` AV properties below:
    ///
    /// - **Writes** happen exclusively on `sessionQueue` (a serial queue) from
    ///   `configureDeviceInput`, `configurePhotoOutput`, `flipCamera`, and
    ///   `capturePhoto`'s dispatched block. The `nonisolated` annotation lets
    ///   these run from outside MainActor; `(unsafe)` acknowledges that Swift
    ///   can't verify the discipline, only the code review can.
    /// - **Reads** from MainActor (e.g. `capturePhoto` reading `photoOutput`)
    ///   snapshot the property into a local `let` before dispatching work to
    ///   `sessionQueue`. The local is then what the dispatched block uses, so
    ///   even if the underlying property is reassigned between snapshot and
    ///   block execution, the block sees the value that was live at call time.
    /// - **`captureSession`** is a `let` so it's safe to read anywhere; the
    ///   AVCaptureSession methods themselves serialize internally.
    ///
    /// This mirrors the pattern in `CameraViewModel` for video recording.
    nonisolated(unsafe) let captureSession = AVCaptureSession()
    nonisolated(unsafe) private var videoInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var photoOutput: AVCapturePhotoOutput?
    nonisolated(unsafe) private var videoDevice: AVCaptureDevice?

    private let sessionQueue = DispatchQueue(label: "com.playerpath.photocamera")

    /// Preview layer is handed to us by `PhotoCameraPreview` once it exists.
    /// Needed both for the RotationCoordinator and for accurate tap-to-focus
    /// coordinate conversion via `captureDevicePointConverted(fromLayerPoint:)`.
    weak var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet { configureRotationCoordinatorIfReady() }
    }

    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewAngleCancellable: AnyCancellable?
    private var captureAngleCancellable: AnyCancellable?
    nonisolated(unsafe) private var currentCaptureAngle: CGFloat = 90

    // Session interruption observers — picked up from AVCaptureSession
    // notifications so the camera doesn't silently freeze when a phone call,
    // Siri session, or other client takes over the capture pipeline.
    private var interruptionObserver: NSObjectProtocol?
    private var interruptionEndObserver: NSObjectProtocol?

    private var zoomGestureBase: CGFloat = 1.0
    private var focusResetTask: Task<Void, Never>?
    private var hasStartedSession = false
    @MainActor private var startupTask: Task<Void, Never>?

    private enum Constants {
        static let defaultZoom: CGFloat = 1.0
        static let clampedMaxZoom: CGFloat = 10.0
    }

    // MARK: Init / Lifecycle

    override init() {
        super.init()
        startupTask = Task { [weak self] in
            await self?.start()
        }
    }

    deinit {
        let session = captureSession
        sessionQueue.async { session.stopRunning() }
    }

    @MainActor
    func start() async {
        guard !hasStartedSession else { return }
        hasStartedSession = true

        await checkPermissions()
        guard !isFatalError else { return }

        let desiredPosition = cameraPosition

        setupInterruptionObservers()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            if self.captureSession.canSetSessionPreset(.photo) {
                self.captureSession.sessionPreset = .photo
            }
            self.configureDeviceInput(for: desiredPosition)
            self.configurePhotoOutput()
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()

            Task { @MainActor [weak self] in
                self?.isSessionReady = true
                self?.configureRotationCoordinatorIfReady()
            }
        }
    }

    @MainActor
    func stop() {
        startupTask?.cancel()
        startupTask = nil

        previewAngleCancellable?.cancel()
        captureAngleCancellable?.cancel()
        previewAngleCancellable = nil
        captureAngleCancellable = nil
        rotationCoordinator = nil

        removeInterruptionObservers()

        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }

        isSessionReady = false
        hasStartedSession = false
    }

    // MARK: Session Interruption

    /// Observe `wasInterruptedNotification` / `interruptionEndedNotification`
    /// so a phone call, Siri session, or other capture client doesn't leave
    /// the preview frozen with no user feedback. Mirrors the behavior in
    /// `CameraViewModel` for video recording.
    @MainActor
    private func setupInterruptionObservers() {
        removeInterruptionObservers()

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: captureSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Drop any in-flight capture state so the shutter isn't stuck
                // disabled if the interruption fired mid-capture.
                self.isCapturing = false
                self.handleError(
                    "Camera was interrupted. It will resume when the other app finishes.",
                    isFatal: false
                )
            }
        }

        interruptionEndObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: captureSession,
            queue: .main
        ) { [weak self] _ in
            // AVFoundation requires an explicit `startRunning()` to resume
            // after an interruption — the session does not auto-recover.
            guard let self else { return }
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
            }
        }
    }

    @MainActor
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

    // MARK: Permissions

    @MainActor
    private func checkPermissions() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                handleError("Camera access denied.", isFatal: true, needsSettings: true)
            }
        case .denied, .restricted:
            handleError(
                "Camera access is turned off. Open Settings to enable it.",
                isFatal: true,
                needsSettings: true
            )
        @unknown default:
            handleError("Camera access unavailable.", isFatal: true, needsSettings: true)
        }
    }

    // MARK: Device Selection

    nonisolated private func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let priority: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        for type in priority {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) {
                return device
            }
        }
        return nil
    }

    nonisolated private func configureDeviceInput(for position: AVCaptureDevice.Position) {
        if let existing = videoInput {
            captureSession.removeInput(existing)
            videoInput = nil
        }

        guard let device = bestDevice(for: position) else {
            Task { @MainActor in
                self.handleError("Camera not available.", isFatal: true)
            }
            return
        }

        videoDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                videoInput = input

                let deviceMin = device.minAvailableVideoZoomFactor
                let deviceMax = device.maxAvailableVideoZoomFactor
                Task { @MainActor in
                    self.minZoom = deviceMin
                    self.maxZoom = min(deviceMax, Constants.clampedMaxZoom)
                    self.currentZoom = max(Constants.defaultZoom, deviceMin)
                    self.zoomGestureBase = self.currentZoom
                }
            }
        } catch {
            Task { @MainActor in
                self.handleError("Failed to configure camera: \(error.localizedDescription)", isFatal: true)
            }
        }
    }

    nonisolated private func configurePhotoOutput() {
        if let existing = photoOutput {
            captureSession.removeOutput(existing)
            photoOutput = nil
        }

        let output = AVCapturePhotoOutput()
        // Opt into Smart HDR / Deep Fusion / Night Mode when the device
        // supports them. Default is `.balanced`, which caps per-shot settings
        // at the same level — bumping this to `.quality` is a prerequisite
        // for requesting `.quality` on AVCapturePhotoSettings. Must be set
        // BEFORE addOutput(_:) — Apple's documented pattern; some iOS versions
        // ignore the assignment if it happens after the output joins the session.
        output.maxPhotoQualityPrioritization = .quality
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            photoOutput = output
        }
    }

    // MARK: Rotation Coordinator

    private func configureRotationCoordinatorIfReady() {
        guard let device = videoDevice,
              let preview = previewLayer else {
            return
        }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
        rotationCoordinator = coordinator

        previewAngleCancellable?.cancel()
        captureAngleCancellable?.cancel()

        currentCaptureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
        applyPreviewAngle(coordinator.videoRotationAngleForHorizonLevelPreview)

        previewAngleCancellable = coordinator.publisher(
            for: \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] angle in
            self?.applyPreviewAngle(angle)
        }

        captureAngleCancellable = coordinator.publisher(
            for: \.videoRotationAngleForHorizonLevelCapture,
            options: [.new]
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] angle in
            self?.currentCaptureAngle = angle
        }
    }

    private func applyPreviewAngle(_ angle: CGFloat) {
        guard let previewLayer, let connection = previewLayer.connection else { return }
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    // MARK: Flip

    func flipCamera() {
        let next: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
        cameraPosition = next
        zoomGestureBase = 1.0
        currentZoom = 1.0

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            self.configureDeviceInput(for: next)
            self.captureSession.commitConfiguration()

            Task { @MainActor [weak self] in
                self?.configureRotationCoordinatorIfReady()
            }
        }
        Haptics.medium()
    }

    // MARK: Flash

    func toggleFlash() {
        // Haptic is fired by the calling button (`PhotoChromeIconButton`).
        // Cycle order matches native iOS Camera: auto → on → off → auto.
        // Starting from the default (.auto), the first tap turns flash ON,
        // which is what users expect from a quick-shot flash tap.
        switch flashMode {
        case .auto: flashMode = .on
        case .on: flashMode = .off
        case .off: flashMode = .auto
        @unknown default: flashMode = .auto
        }
    }

    // MARK: Zoom

    func handlePinch(scale: CGFloat) {
        let target = min(max(zoomGestureBase * scale, minZoom), maxZoom)
        setZoom(target)
    }

    func endPinch() {
        zoomGestureBase = currentZoom
    }

    /// Pill taps — ramp smoothly to the target factor so the preview glides
    /// instead of snapping. The pill highlight updates instantly (currentZoom
    /// is set to the target on the main actor) while the device catches up
    /// over ~100–250ms depending on the jump size.
    func jumpToZoom(_ factor: CGFloat) {
        let clamped = min(max(factor, minZoom), maxZoom)
        currentZoom = clamped
        zoomGestureBase = clamped
        Haptics.light()

        guard let device = videoDevice else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                // Rate ~8.0 = zoom doubles/halves ~8× per second — a 1×→2×
                // jump lands in ~125ms, which reads as smooth but snappy.
                device.ramp(toVideoZoomFactor: clamped, withRate: 8.0)
                device.unlockForConfiguration()
            } catch {
                photoLog.warning("Zoom ramp failed: \(error.localizedDescription)")
            }
        }
    }

    func setZoom(_ zoom: CGFloat) {
        guard let device = videoDevice else { return }
        currentZoom = zoom
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                // Cancel any in-flight ramp from a recent pill tap — setting
                // videoZoomFactor while a ramp is active produces undefined
                // behavior per AVFoundation, so pinch-during-ramp must stop
                // the ramp before writing the new factor.
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = zoom
                device.unlockForConfiguration()
            } catch {
                photoLog.warning("Failed to set zoom: \(error.localizedDescription)")
            }
        }
    }

    var hasUltraWide: Bool {
        minZoom < 0.9
    }

    var hasTelephoto: Bool {
        AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: cameraPosition) != nil
    }

    // MARK: Focus

    func handleTapToFocus(atLayerPoint point: CGPoint) {
        guard let device = videoDevice,
              let previewLayer,
              previewLayer.bounds.contains(point) else { return }

        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

        lastFocusPoint = point
        focusResetTask?.cancel()
        focusResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                await MainActor.run {
                    self?.lastFocusPoint = nil
                }
            }
        }

        Haptics.light()

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
                photoLog.warning("Failed to set focus: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Capture

    func capturePhoto() {
        guard isSessionReady, !isCapturing, let output = photoOutput else { return }

        // Reset the last captured image so the view's `.onChange(of:)` observer
        // fires reliably if this capture produces a new UIImage instance that
        // would otherwise compare equal. Also drops the reference so the prior
        // image can deallocate promptly instead of sitting in memory until VM
        // dealloc — important if the flow ever allows multiple captures per
        // session.
        capturedImage = nil

        isCapturing = true
        let flash = flashMode
        let captureAngle = currentCaptureAngle

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if let connection = output.connection(with: .video),
               connection.isVideoRotationAngleSupported(captureAngle) {
                connection.videoRotationAngle = captureAngle
            }

            let settings = AVCapturePhotoSettings()
            if output.supportedFlashModes.contains(flash) {
                settings.flashMode = flash
            } else {
                settings.flashMode = .off
            }
            // Opt into Smart HDR / Deep Fusion / Night Mode. Adds 100ms–1s of
            // processing before the delegate fires on older devices or in low
            // light, but produces noticeably better output for profile pics,
            // posed shots, and dim-gym action — the domains this camera serves.
            settings.photoQualityPrioritization = .quality

            output.capturePhoto(with: settings, delegate: self)
        }

        Haptics.medium()
    }

    // MARK: Error

    private func handleError(_ message: String, isFatal: Bool, needsSettings: Bool = false) {
        currentError = message
        self.isFatalError = isFatal
        errorNeedsSettings = needsSettings
        showingError = true
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension PhotoCameraViewModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.isCapturing = false
                self.handleError("Photo capture failed: \(error.localizedDescription)", isFatal: false)
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task { @MainActor in
                self.isCapturing = false
                self.handleError("Photo capture returned no data.", isFatal: false)
            }
            return
        }

        Task { @MainActor in
            self.isCapturing = false
            self.capturedImage = image
            Haptics.success()
        }
    }
}
