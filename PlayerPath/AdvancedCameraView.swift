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
    
    // MARK: - Properties
    
    var settings: VideoRecordingSettings = .shared
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
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupCamera()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.stopRunning()
            }
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
        settingsLabel.layer.cornerRadius = 8
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
            slowMotionIndicator.layer.cornerRadius = 8
            
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
                slowMotionIndicator.widthAnchor.constraint(equalToConstant: 100),
                slowMotionIndicator.heightAnchor.constraint(equalToConstant: 32)
            ])
        }
        
        // Record button
        recordButton.backgroundColor = .red
        recordButton.layer.cornerRadius = 40
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
            settingsLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            settingsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            settingsLabel.heightAnchor.constraint(equalToConstant: 32),
            
            recordingTimeLabel.topAnchor.constraint(equalTo: settingsLabel.bottomAnchor, constant: 16),
            recordingTimeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            recordButton.widthAnchor.constraint(equalToConstant: 80),
            recordButton.heightAnchor.constraint(equalToConstant: 80),
            
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            
            flipCameraButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            flipCameraButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            flipCameraButton.widthAnchor.constraint(equalToConstant: 44),
            flipCameraButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        if settings.slowMotionEnabled {
            NSLayoutConstraint.activate([
                slowMotionIndicator.topAnchor.constraint(equalTo: recordingTimeLabel.bottomAnchor, constant: 16),
                slowMotionIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            ])
        }
    }
    
    private func setupCamera() {
        // Configure session preset based on quality
        captureSession.sessionPreset = settings.quality.avPreset
        
        // Get camera device
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("❌ Failed to get camera device")
            return
        }
        
        videoDevice = device
        
        // Configure device settings
        do {
            try device.lockForConfiguration()
            
            // Set frame rate
            let targetFPS = settings.frameRate.fps
            if let formatForFPS = findFormatForFrameRate(device: device, targetFPS: targetFPS) {
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
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                videoInput = input
            }
        } catch {
            print("❌ Failed to add video input: \(error)")
        }
        
        // Add audio input if enabled
        if settings.audioEnabled {
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                do {
                    let input = try AVCaptureDeviceInput(device: audioDevice)
                    if captureSession.canAddInput(input) {
                        captureSession.addInput(input)
                        audioInput = input
                    }
                } catch {
                    print("❌ Failed to add audio input: \(error)")
                }
            }
        }
        
        // Add movie file output
        let output = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            movieFileOutput = output
            
            // Configure output settings
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
        }
        
        // Setup preview layer
        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
    }
    
    private func findFormatForFrameRate(device: AVCaptureDevice, targetFPS: Int) -> AVCaptureDevice.Format? {
        let formats = device.formats
        
        for format in formats {
            let ranges = format.videoSupportedFrameRateRanges
            for range in ranges {
                if Int(range.maxFrameRate) >= targetFPS {
                    return format
                }
            }
        }
        
        return nil
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.onCancel?()
            }
        } else {
            onCancel?()
        }
    }
    
    @objc private func flipCameraButtonTapped() {
        guard let currentInput = videoInput else { return }
        
        captureSession.beginConfiguration()
        captureSession.removeInput(currentInput)
        
        let newPosition: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back
        
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
            captureSession.addInput(currentInput)
            captureSession.commitConfiguration()
            return
        }
        
        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
            videoInput = newInput
            videoDevice = newDevice
        }
        
        captureSession.commitConfiguration()
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
        startRecordingTimer()
        
        UIView.animate(withDuration: 0.2) {
            self.recordButton.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            self.recordButton.layer.cornerRadius = 8
        }
        
        recordingTimeLabel.isHidden = false
        flipCameraButton.isEnabled = false
    }
    
    private func stopRecording() {
        guard let output = movieFileOutput, output.isRecording else { return }
        
        output.stopRecording()
        stopRecordingTimer()
        
        // Update UI
        isRecording = false
        
        UIView.animate(withDuration: 0.2) {
            self.recordButton.transform = .identity
            self.recordButton.layer.cornerRadius = 40
        }
        
        flipCameraButton.isEnabled = true
    }
    
    // MARK: - Recording Timer
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
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
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
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
