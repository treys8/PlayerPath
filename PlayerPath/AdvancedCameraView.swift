//
//  AdvancedCameraView.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import SwiftUI
import AVFoundation
import UIKit

/// Advanced camera view with full control over quality, format, frame rate, and slow-motion
struct AdvancedCameraView: UIViewControllerRepresentable {
    let settings: VideoRecordingSettings
    let onVideoRecorded: (URL) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> AdvancedCameraViewController {
        let controller = AdvancedCameraViewController()
        controller.settings = settings
        controller.onVideoRecorded = onVideoRecorded
        controller.onCancel = onCancel
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AdvancedCameraViewController, context: Context) {
        // Updates handled by controller
    }
}

// MARK: - Advanced Camera View Controller

class AdvancedCameraViewController: UIViewController {

    // MARK: - Constants

    private enum Constants {
        // Recording duration
        static let maxRecordingDuration: TimeInterval = 600 // 10 minutes (matches VideoRecorderView)
        static let warningDuration: TimeInterval = 480 // 8 minutes

        // UI Layout
        static let standardSpacing: CGFloat = 16
        static let edgeSpacing: CGFloat = 20
        static let buttonBottomOffset: CGFloat = -40
        static let settingsLabelHeight: CGFloat = 32
        static let slowMotionIndicatorWidth: CGFloat = 100
        static let slowMotionIndicatorHeight: CGFloat = 32

        // Button sizes
        static let recordButtonSize: CGFloat = 80
        static let recordButtonCornerRadius: CGFloat = 40
        static let recordButtonSmallCornerRadius: CGFloat = 8
        static let flipCameraButtonSize: CGFloat = 44

        // Animation
        static let standardAnimationDuration: TimeInterval = 0.2
        static let recordingTimerInterval: TimeInterval = 0.1
        static let warningFlashDuration: TimeInterval = 2.0
        static let recordButtonScale: CGFloat = 0.7
        static let cancelDelayDuration: TimeInterval = 0.3
    }

    // MARK: - Properties

    var settings: VideoRecordingSettings!
    var onVideoRecorded: ((URL) -> Void)?
    var onCancel: (() -> Void)?

    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var isRecording = false
    private var outputURL: URL?
    
    // UI Elements
    private let recordButton = UIButton(type: .custom)
    private let cancelButton = UIButton(type: .system)
    private let flipCameraButton = UIButton(type: .system)
    private let settingsLabel = UILabel()
    private let recordingTimeLabel = UILabel()
    private let slowMotionIndicator = UIView()
    
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var hasShownDurationWarning = false

    // MARK: - Lifecycle
    
    deinit {
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
                captureSession.stopRunning()
            }
        }
        
        previewLayer?.removeFromSuperlayer()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupCamera()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }
    
    override var shouldAutorotate: Bool {
        return true
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Settings label at top
        settingsLabel.textColor = .white
        settingsLabel.font = .systemFont(ofSize: 14, weight: .medium)
        settingsLabel.textAlignment = .center
        settingsLabel.text = settings.settingsDescription
        settingsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        settingsLabel.layer.cornerRadius = Constants.recordButtonSmallCornerRadius
        settingsLabel.layer.masksToBounds = true
        settingsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(settingsLabel)
        
        // Recording time label
        recordingTimeLabel.textColor = .red
        recordingTimeLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        recordingTimeLabel.textAlignment = .center
        recordingTimeLabel.isHidden = true
        recordingTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recordingTimeLabel)
        
        // Slow-motion indicator
        if settings.slowMotionEnabled {
            slowMotionIndicator.backgroundColor = UIColor.purple.withAlphaComponent(0.8)
            slowMotionIndicator.layer.cornerRadius = Constants.recordButtonSmallCornerRadius

            let slowMoLabel = UILabel()
            slowMoLabel.text = "SLOW-MO"
            slowMoLabel.textColor = .white
            slowMoLabel.font = .systemFont(ofSize: 12, weight: .bold)
            slowMoLabel.translatesAutoresizingMaskIntoConstraints = false

            slowMotionIndicator.addSubview(slowMoLabel)
            slowMotionIndicator.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(slowMotionIndicator)

            NSLayoutConstraint.activate([
                slowMoLabel.centerXAnchor.constraint(equalTo: slowMotionIndicator.centerXAnchor),
                slowMoLabel.centerYAnchor.constraint(equalTo: slowMotionIndicator.centerYAnchor),
                slowMotionIndicator.widthAnchor.constraint(equalToConstant: Constants.slowMotionIndicatorWidth),
                slowMotionIndicator.heightAnchor.constraint(equalToConstant: Constants.slowMotionIndicatorHeight)
            ])
        }
        
        // Record button
        recordButton.backgroundColor = .red
        recordButton.layer.cornerRadius = Constants.recordButtonCornerRadius
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recordButton)
        
        // Cancel button
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)
        
        // Flip camera button
        flipCameraButton.setImage(UIImage(systemName: "camera.rotate"), for: .normal)
        flipCameraButton.tintColor = .white
        flipCameraButton.addTarget(self, action: #selector(flipCameraButtonTapped), for: .touchUpInside)
        flipCameraButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(flipCameraButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            settingsLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.standardSpacing),
            settingsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            settingsLabel.heightAnchor.constraint(equalToConstant: Constants.settingsLabelHeight),

            recordingTimeLabel.topAnchor.constraint(equalTo: settingsLabel.bottomAnchor, constant: Constants.standardSpacing),
            recordingTimeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: Constants.buttonBottomOffset),
            recordButton.widthAnchor.constraint(equalToConstant: Constants.recordButtonSize),
            recordButton.heightAnchor.constraint(equalToConstant: Constants.recordButtonSize),

            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Constants.edgeSpacing),
            cancelButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),

            flipCameraButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Constants.edgeSpacing),
            flipCameraButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            flipCameraButton.widthAnchor.constraint(equalToConstant: Constants.flipCameraButtonSize),
            flipCameraButton.heightAnchor.constraint(equalToConstant: Constants.flipCameraButtonSize)
        ])
        
        if settings.slowMotionEnabled {
            NSLayoutConstraint.activate([
                slowMotionIndicator.topAnchor.constraint(equalTo: recordingTimeLabel.bottomAnchor, constant: Constants.standardSpacing),
                slowMotionIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            ])
        }
    }
    
    private func setupCamera() {
        // Check camera authorization first
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authStatus == .authorized else {
            if authStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    if granted {
                        DispatchQueue.main.async {
                            self?.setupCamera()
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.showPermissionDeniedUI()
                        }
                    }
                }
            } else {
                showPermissionDeniedUI()
            }
            return
        }

        // Capture settings values before async boundary (MainActor isolation)
        let qualityPreset = settings.quality.avPreset
        let targetFPS = settings.frameRate.fps
        let audioEnabled = settings.audioEnabled
        let stabilizationMode = settings.stabilizationMode.avMode

        // Perform heavy camera setup on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Validate settings and warn user
            let warnings = self.validateSettings()
            if !warnings.isEmpty {
                #if DEBUG
                print("⚠️ Camera settings warnings: \(warnings.joined(separator: ", "))")
                #endif
            }

            // Configure session preset based on quality
            self.captureSession.sessionPreset = qualityPreset

            // Get camera device
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("❌ Failed to get camera device")
                return
            }

            self.videoDevice = device

            // Configure device settings
            do {
                try device.lockForConfiguration()

                // Set frame rate
                if let formatForFPS = self.findFormatForFrameRate(device: device, targetFPS: targetFPS) {
                    device.activeFormat = formatForFPS
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))

                    #if DEBUG
                    print("✅ Set frame rate to \(targetFPS) fps")
                    #endif
                }

                device.unlockForConfiguration()
            } catch {
                print("❌ Failed to configure device: \(error)")
            }

            // Add video input
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                    self.videoInput = input
                }
            } catch {
                print("❌ Failed to add video input: \(error)")
            }

            // Add audio input if enabled
            if audioEnabled {
                if let audioDevice = AVCaptureDevice.default(for: .audio) {
                    do {
                        let input = try AVCaptureDeviceInput(device: audioDevice)
                        if self.captureSession.canAddInput(input) {
                            self.captureSession.addInput(input)
                            self.audioInput = input
                        }
                    } catch {
                        print("❌ Failed to add audio input: \(error)")
                    }
                }
            }

            // Add movie file output
            let output = AVCaptureMovieFileOutput()
            if self.captureSession.canAddOutput(output) {
                self.captureSession.addOutput(output)
                self.movieFileOutput = output

                // Configure output settings
                if let connection = output.connection(with: .video) {
                    // Set stabilization
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = stabilizationMode
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
            }

            // Setup preview layer on main thread (UI operation)
            DispatchQueue.main.async {
                let preview = AVCaptureVideoPreviewLayer(session: self.captureSession)
                preview.videoGravity = .resizeAspectFill
                preview.frame = self.view.bounds
                self.view.layer.insertSublayer(preview, at: 0)
                self.previewLayer = preview
            }
        }
    }
    
    private func findFormatForFrameRate(device: AVCaptureDevice, targetFPS: Int) -> AVCaptureDevice.Format? {
        let formats = device.formats
        
        for format in formats {
            let ranges = format.videoSupportedFrameRateRanges
            for range in ranges {
                if Int(range.minFrameRate) <= targetFPS && Int(range.maxFrameRate) >= targetFPS {
                    return format
                }
            }
        }
        
        return nil
    }
    
    private func validateSettings() -> [String] {
        var warnings: [String] = []
        
        // Check 4K60 + stabilization compatibility
        if settings.quality == .ultra4K && settings.frameRate.fps >= 60 && settings.stabilizationMode != .off {
            warnings.append("4K60 with stabilization may not be supported on all devices")
        }
        
        // Check slow-motion + quality compatibility
        if settings.slowMotionEnabled && settings.quality == .ultra4K {
            warnings.append("Slow-motion at 4K may have limited support")
        }
        
        // Check high frame rate availability
        if settings.frameRate.fps >= 120 {
            warnings.append("120+ fps requires compatible device and may reduce resolution")
        }
        
        return warnings
    }
    
    // MARK: - Actions
    
    @objc private func recordButtonTapped() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    @objc private func cancelButtonTapped() {
        if isRecording {
            stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.cancelDelayDuration) { [weak self] in
                self?.onCancel?()
            }
        } else {
            onCancel?()
        }
    }
    
    @objc private func flipCameraButtonTapped() {
        guard let currentInput = videoInput else { return }

        // Disable button during transition
        flipCameraButton.isEnabled = false

        // Perform camera switch on background queue to avoid UI freeze
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()
            self.captureSession.removeInput(currentInput)

            let newPosition: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back

            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                self.captureSession.addInput(currentInput)
                self.captureSession.commitConfiguration()
                // Re-enable button on main thread
                DispatchQueue.main.async {
                    self.flipCameraButton.isEnabled = true
                }
                return
            }

            if self.captureSession.canAddInput(newInput) {
                self.captureSession.addInput(newInput)
                self.videoInput = newInput
                self.videoDevice = newDevice
            }

            self.captureSession.commitConfiguration()

            // Re-enable button on main thread
            DispatchQueue.main.async {
                self.flipCameraButton.isEnabled = true
            }
        }
    }
    
    private func startRecording() {
        guard let output = movieFileOutput else { return }

        // Generate output URL
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).\(settings.format.fileExtension)")
        outputURL = outputPath

        // Start recording
        output.startRecording(to: outputPath, recordingDelegate: self)

        // Update UI
        isRecording = true
        recordingStartTime = Date()
        hasShownDurationWarning = false  // Reset warning flag for new recording
        startRecordingTimer()

        UIView.animate(withDuration: Constants.standardAnimationDuration) {
            self.recordButton.transform = CGAffineTransform(scaleX: Constants.recordButtonScale, y: Constants.recordButtonScale)
            self.recordButton.layer.cornerRadius = Constants.recordButtonSmallCornerRadius
        }

        recordingTimeLabel.isHidden = false
        flipCameraButton.isEnabled = false
    }
    
    private func stopRecording() {
        guard let output = movieFileOutput else { return }
        guard output.isRecording else {
            // Already stopped, just clean up UI
            isRecording = false
            stopRecordingTimer()
            return
        }
        
        output.stopRecording()
        stopRecordingTimer()
        
        // Update UI
        isRecording = false

        UIView.animate(withDuration: Constants.standardAnimationDuration) {
            self.recordButton.transform = .identity
            self.recordButton.layer.cornerRadius = Constants.recordButtonCornerRadius
        }
        
        flipCameraButton.isEnabled = true
    }
    
    // MARK: - Recording Timer
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: Constants.recordingTimerInterval, repeats: true) { [weak self] _ in
            self?.updateRecordingTime()
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingTimeLabel.isHidden = true
    }
    
    private func updateRecordingTime() {
        guard let startTime = recordingStartTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let milliseconds = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 10)

        recordingTimeLabel.text = String(format: "%02d:%02d.%01d", minutes, seconds, milliseconds)

        // Show warning at 8 minutes
        if elapsed >= Constants.warningDuration && !hasShownDurationWarning {
            hasShownDurationWarning = true
            showDurationWarning()
        }

        // Automatically stop recording at max duration (10 minutes)
        if elapsed >= Constants.maxRecordingDuration {
            #if DEBUG
            print("⏱️ Max recording duration (\(Int(Constants.maxRecordingDuration))s) reached, stopping automatically")
            #endif
            stopRecording()
        }
    }

    private func showDurationWarning() {
        // Flash the recording time label to warn user
        UIView.animate(withDuration: Constants.standardAnimationDuration, delay: 0, options: [.autoreverse, .repeat]) {
            self.recordingTimeLabel.alpha = 0.3
        }

        // Reset alpha after warning flash duration
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.warningFlashDuration) {
            UIView.animate(withDuration: Constants.standardAnimationDuration, delay: 0, options: []) {
                self.recordingTimeLabel.alpha = 1.0
            }
        }

        // Provide haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        #if DEBUG
        print("⚠️ Recording duration warning: 2 minutes remaining")
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    private func showPermissionDeniedUI() {
        let alert = UIAlertController(
            title: "Camera Access Required",
            message: "Please enable camera access in Settings to record videos.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.onCancel?()
        })
        present(alert, animated: true)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension AdvancedCameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("❌ Recording error: \(error.localizedDescription)")
            return
        }
        
        #if DEBUG
        print("✅ Recording finished: \(outputFileURL.path)")
        #endif
        
        DispatchQueue.main.async { [weak self] in
            self?.onVideoRecorded?(outputFileURL)
        }
    }
}
