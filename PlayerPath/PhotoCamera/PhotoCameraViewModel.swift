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

// `nonisolated` because the project builds with SWIFT_DEFAULT_ACTOR_ISOLATION =
// MainActor, and this is logged from the session queue. Matches the pattern in
// SyncCoordinator+Photos, ScorecardOCR, etc.
nonisolated private let photoLog = Logger(subsystem: "com.playerpath.app", category: "PhotoCamera")

@MainActor
class PhotoCameraViewModel: NSObject, ObservableObject {

    // MARK: Published State

    @Published var isSessionReady = false
    @Published var isCapturing = false
    @Published var capturedImage: UIImage?

    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    @Published var cameraPosition: AVCaptureDevice.Position = .back

    /// All three are **display** zoom — what the pills show (0.5×, 1×, 2×…) —
    /// never the raw device `videoZoomFactor`. See `zoomBaseFactor` for why the
    /// two spaces are not the same thing on a multi-camera iPhone.
    @Published var currentZoom: CGFloat = 1.0
    @Published var minZoom: CGFloat = 1.0
    @Published var maxZoom: CGFloat = 10.0

    /// True when the active device has an optical telephoto constituent.
    /// Stored rather than computed so the zoom pills don't run an
    /// `AVCaptureDevice` discovery on every SwiftUI body evaluation.
    @Published private(set) var hasTelephoto: Bool = false

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

    /// Device `videoZoomFactor` that corresponds to a **display** zoom of 1.0×.
    ///
    /// On a virtual multi-camera device (triple / dual-wide) factor 1.0 selects
    /// the *ultra-wide* lens, not the 1× wide lens — so publishing raw device
    /// factors would label an ultra-wide frame "1×" and hide the 0.5× stop
    /// entirely. Everything this class publishes is therefore display zoom, and
    /// this base is applied only where `videoZoomFactor` is actually written.
    /// Follows the same snapshot-then-dispatch contract as the properties above.
    nonisolated(unsafe) private var zoomBaseFactor: CGFloat = 1.0

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

    // Session observers — interruption (phone call, Siri, another capture
    // client) and runtime error (media services reset), so the camera doesn't
    // silently freeze with no user feedback and no way back.
    private var interruptionObserver: NSObjectProtocol?
    private var interruptionEndObserver: NSObjectProtocol?
    private var runtimeErrorObserver: NSObjectProtocol?

    private var zoomGestureBase: CGFloat = 1.0
    private var focusResetTask: Task<Void, Never>?
    private var captureTimeoutTask: Task<Void, Never>?
    private var hasStartedSession = false
    @MainActor private var startupTask: Task<Void, Never>?

    /// Bumped by `stop()` and by media-services recovery. Work dispatched to
    /// `sessionQueue` carries the generation it was started under and drops its
    /// MainActor completion if the value has moved on — otherwise a teardown
    /// that races an in-flight startup gets its state stomped back (see the
    /// `isSessionReady` handling in `configureAndStartSession`).
    private var sessionGeneration = 0

    // `nonisolated` members: these are read on the session queue from
    // `configureDeviceInput`, and the project defaults to MainActor isolation.
    private enum Constants {
        nonisolated static let defaultZoom: CGFloat = 1.0
        nonisolated static let clampedMaxZoom: CGFloat = 10.0
        /// Upper bound on how long `isCapturing` may stay latched waiting for a
        /// delegate callback that may never arrive.
        ///
        /// Deliberately generous: this is a stuck-shutter backstop, not a
        /// latency budget. `photoQualityPrioritization = .quality` opts into
        /// Night Mode, whose exposures legitimately run many seconds in low
        /// light — a tight timeout would fire on a perfectly good capture and
        /// show a spurious failure alert while the photo was still processing.
        static let captureTimeout: TimeInterval = 30
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
        // `stop()` can run while the permission prompt is up — it clears the
        // flag we just set, which is the signal that this startup is stale.
        guard hasStartedSession else { return }

        sessionGeneration += 1
        let generation = sessionGeneration
        let desiredPosition = cameraPosition

        setupSessionObservers()
        configureAndStartSession(position: desiredPosition, generation: generation)
    }

    /// Full session build: preset → input → output → run.
    ///
    /// Shared by `start()` and by the media-services-reset recovery path, which
    /// has to rebuild the entire capture stack rather than merely call
    /// `startRunning()` again.
    @MainActor
    private func configureAndStartSession(position: AVCaptureDevice.Position, generation: Int) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            if self.captureSession.canSetSessionPreset(.photo) {
                self.captureSession.sessionPreset = .photo
            }
            self.configureDeviceInput(for: position, generation: generation)
            self.configurePhotoOutput()
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()

            Task { @MainActor [weak self] in
                // A `stop()` (or another rebuild) that landed while this block
                // was running bumped the generation. Without this check the
                // stale completion re-enables the shutter over a dead session.
                guard let self, self.sessionGeneration == generation else { return }
                self.isSessionReady = true
                self.configureRotationCoordinatorIfReady()
            }
        }
    }

    @MainActor
    func stop() {
        sessionGeneration += 1

        startupTask?.cancel()
        startupTask = nil

        captureTimeoutTask?.cancel()
        captureTimeoutTask = nil

        focusResetTask?.cancel()
        focusResetTask = nil

        previewAngleCancellable?.cancel()
        captureAngleCancellable?.cancel()
        previewAngleCancellable = nil
        captureAngleCancellable = nil
        rotationCoordinator = nil

        removeSessionObservers()

        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }

        isSessionReady = false
        isCapturing = false
        hasStartedSession = false
    }

    // MARK: Session Observers

    /// Observe `wasInterrupted` / `interruptionEnded` / `runtimeError` so a
    /// phone call, Siri session, other capture client, or a media services
    /// reset doesn't leave the preview frozen with no user feedback.
    @MainActor
    private func setupSessionObservers() {
        removeSessionObservers()

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: captureSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Drop any in-flight capture state so the shutter isn't stuck
                // disabled if the interruption fired mid-capture.
                self.finishCapture()
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

        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: captureSession,
            queue: .main
        ) { [weak self] note in
            // Pull the raw code out here rather than carrying the Notification
            // across the actor hop — an Int is trivially Sendable.
            let code = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.code
            Task { @MainActor [weak self] in
                self?.handleRuntimeError(code: code)
            }
        }
    }

    @MainActor
    private func removeSessionObservers() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = interruptionEndObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionEndObserver = nil
        }
        if let observer = runtimeErrorObserver {
            NotificationCenter.default.removeObserver(observer)
            runtimeErrorObserver = nil
        }
    }

    /// A runtime error stops the session for good — unlike an interruption,
    /// nothing resumes on its own.
    @MainActor
    private func handleRuntimeError(code: Int?) {
        photoLog.error("Capture session runtime error: \(code ?? 0)")
        finishCapture()
        // The session is down either way — leaving this true keeps the shutter
        // tappable over a preview that will never update again.
        isSessionReady = false

        guard code == AVError.Code.mediaServicesWereReset.rawValue else {
            handleError("Camera stopped unexpectedly. Please close and reopen the camera.", isFatal: false)
            return
        }

        // A media services reset invalidates the whole capture stack: inputs
        // and outputs have to be rebuilt, not just restarted.
        sessionGeneration += 1
        configureAndStartSession(position: cameraPosition, generation: sessionGeneration)
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

    /// The device `videoZoomFactor` at which the **wide** (1×) lens is active.
    ///
    /// A virtual device lists its constituents widest-first, so when the first
    /// one is the ultra-wide, factor 1.0 *is* the ultra-wide and true 1× lives
    /// at the first switch-over point (2.0 on current iPhones). Physical
    /// devices report no constituents, and `.builtInDualCamera` (wide +
    /// telephoto, no ultra-wide) is already 1.0-based — both correctly fall
    /// through to the 1.0 default.
    nonisolated private static func trueOneXZoomFactor(for device: AVCaptureDevice) -> CGFloat {
        guard device.constituentDevices.first?.deviceType == .builtInUltraWideCamera,
              let firstSwitchOver = device.virtualDeviceSwitchOverVideoZoomFactors.first
        else { return 1.0 }
        let factor = CGFloat(truncating: firstSwitchOver)
        return factor > 0 ? factor : 1.0
    }

    /// Display → device factor, clamped against the device's *live* range.
    ///
    /// The clamp has to happen here, on the session queue, for two reasons: the
    /// available factors are format-dependent and can move, and an out-of-range
    /// `videoZoomFactor` write raises an Objective-C exception that a
    /// surrounding `do/catch` cannot catch — it's a crash, not a thrown error.
    nonisolated private static func deviceZoomFactor(
        _ displayZoom: CGFloat,
        base: CGFloat,
        on device: AVCaptureDevice
    ) -> CGFloat {
        min(max(displayZoom * base, device.minAvailableVideoZoomFactor),
            device.maxAvailableVideoZoomFactor)
    }

    nonisolated private func configureDeviceInput(for position: AVCaptureDevice.Position, generation: Int) {
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

                // Translate the device's raw factors into display space before
                // publishing any of them — see `zoomBaseFactor`.
                let base = Self.trueOneXZoomFactor(for: device)
                zoomBaseFactor = base

                let displayMin = device.minAvailableVideoZoomFactor / base
                let displayMax = min(device.maxAvailableVideoZoomFactor / base, Constants.clampedMaxZoom)
                let initialDisplay = min(max(Constants.defaultZoom, displayMin), displayMax)
                let tele = device.constituentDevices.contains { $0.deviceType == .builtInTelephotoCamera }

                // The device carries its own zoom factor and defaults to 1.0 —
                // which on a virtual device selects the ULTRA-WIDE lens.
                // Publishing a display value alone would leave the hardware on
                // the wrong lens until the user first touched a pill, so the
                // opening factor has to be pushed to the device here. Its own
                // do/catch so a zoom failure can't trip the fatal "failed to
                // configure camera" path below.
                do {
                    try device.lockForConfiguration()
                    device.videoZoomFactor = Self.deviceZoomFactor(initialDisplay, base: base, on: device)
                    device.unlockForConfiguration()
                } catch {
                    photoLog.warning("Failed to set initial zoom: \(error.localizedDescription)")
                }

                Task { @MainActor in
                    guard self.sessionGeneration == generation else { return }
                    self.minZoom = displayMin
                    self.maxZoom = displayMax
                    self.currentZoom = initialDisplay
                    self.zoomGestureBase = initialDisplay
                    self.hasTelephoto = tele
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

        // Flipping doesn't tear the session down, so it keeps the current
        // generation — only a `stop()` should invalidate the pending work.
        let generation = sessionGeneration

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            self.configureDeviceInput(for: next, generation: generation)
            self.captureSession.commitConfiguration()

            Task { @MainActor [weak self] in
                guard let self, self.sessionGeneration == generation else { return }
                self.configureRotationCoordinatorIfReady()
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

    // All zoom values crossing these APIs are display zoom (0.5×, 1×, 2×…).
    // The conversion to device factors happens in `deviceZoomFactor`, on the
    // session queue, immediately before the write.

    func handlePinch(scale: CGFloat) {
        // `.opacity(0)` on the preview does not disable hit testing, so pinches
        // are live during startup — before the real zoom bounds are known.
        guard isSessionReady else { return }
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
        guard isSessionReady, let device = videoDevice else { return }

        let clamped = min(max(factor, minZoom), maxZoom)
        currentZoom = clamped
        zoomGestureBase = clamped
        Haptics.light()

        let base = zoomBaseFactor
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                // Rate ~8.0 = zoom doubles/halves ~8× per second — a 1×→2×
                // jump lands in ~125ms, which reads as smooth but snappy.
                device.ramp(
                    toVideoZoomFactor: Self.deviceZoomFactor(clamped, base: base, on: device),
                    withRate: 8.0
                )
                device.unlockForConfiguration()
            } catch {
                photoLog.warning("Zoom ramp failed: \(error.localizedDescription)")
            }
        }
    }

    func setZoom(_ zoom: CGFloat) {
        guard let device = videoDevice else { return }
        currentZoom = zoom

        let base = zoomBaseFactor
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                // Cancel any in-flight ramp from a recent pill tap — setting
                // videoZoomFactor while a ramp is active produces undefined
                // behavior per AVFoundation, so pinch-during-ramp must stop
                // the ramp before writing the new factor.
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = Self.deviceZoomFactor(zoom, base: base, on: device)
                device.unlockForConfiguration()
            } catch {
                photoLog.warning("Failed to set zoom: \(error.localizedDescription)")
            }
        }
    }

    /// Display-space check: on an ultra-wide device the minimum display zoom is
    /// 0.5×, because device factor 1.0 maps to half of true 1×.
    var hasUltraWide: Bool {
        minZoom < 0.9
    }

    // MARK: Focus

    func handleTapToFocus(atLayerPoint point: CGPoint) {
        guard isSessionReady,
              let device = videoDevice,
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

        // Bound the in-flight state. `isCapturing` is otherwise cleared only by
        // the delegate, so a request the output silently drops (session torn
        // down mid-capture, media services reset) would leave the shutter
        // disabled for the rest of the session with no way back.
        captureTimeoutTask?.cancel()
        captureTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.captureTimeout))
            guard !Task.isCancelled, let self, self.isCapturing else { return }
            self.captureTimeoutTask = nil
            self.isCapturing = false
            self.handleError("Photo capture timed out. Please try again.", isFatal: false)
        }

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

    /// Single exit point for the in-flight capture state, so the timeout can
    /// never outlive the capture it was guarding.
    @MainActor
    private func finishCapture() {
        captureTimeoutTask?.cancel()
        captureTimeoutTask = nil
        isCapturing = false
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
                self.finishCapture()
                self.handleError("Photo capture failed: \(error.localizedDescription)", isFatal: false)
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            Task { @MainActor in
                self.finishCapture()
                self.handleError("Photo capture returned no data.", isFatal: false)
            }
            return
        }

        Task { @MainActor in
            self.finishCapture()
            self.capturedImage = image
            Haptics.success()
        }
    }
}
