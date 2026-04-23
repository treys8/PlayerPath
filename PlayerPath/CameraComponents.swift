//
//  CameraComponents.swift
//  PlayerPath
//
//  Extracted from ModernCameraView.swift so the main view file stays focused on
//  layout orchestration. These are reusable building blocks for the video
//  recorder — `CameraPreviewLayer` hosts the AVFoundation preview,
//  `FocusReticleView` and `GridOverlayView` are stateless overlays,
//  `CameraSettingsView` is the video settings sheet, and `CameraButtonRing`
//  is the white ring for the record button.
//

import SwiftUI
import AVFoundation

// MARK: - Orientation Helper

enum CameraOrientation {
    /// Applies the rotation that matches `orientation` to `connection`.
    /// Shared by `CameraPreviewLayer` (preview) and `CameraViewModel` (capture output)
    /// so both stay in lockstep if the mapping ever changes.
    /// `nonisolated` because it only mutates its `connection` argument — called from
    /// AVFoundation callbacks that aren't on the main actor.
    nonisolated static func apply(_ orientation: UIDeviceOrientation, to connection: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            let angle: CGFloat = switch orientation {
            case .landscapeLeft: 0       // Home button on right → natural landscape
            case .landscapeRight: 180    // Home button on left
            case .portraitUpsideDown: 270
            default: 90                  // Portrait (default)
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else {
            let videoOrientation: AVCaptureVideoOrientation = switch orientation {
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
}

// MARK: - Camera Preview Layer

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    let orientation: UIDeviceOrientation
    /// Preview gravity. Video uses `.resizeAspectFill` to fill the screen.
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = gravity
        updatePreviewOrientation(view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.videoGravity = gravity
        updatePreviewOrientation(uiView)
    }

    private func updatePreviewOrientation(_ view: PreviewView) {
        guard let connection = view.videoPreviewLayer.connection else { return }
        CameraOrientation.apply(orientation, to: connection)
    }

    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
                fatalError("Expected AVCaptureVideoPreviewLayer but got \(type(of: layer)) — layerClass override missing")
            }
            return previewLayer
        }
    }
}

// MARK: - Focus Reticle

struct FocusReticleView: View {
    let point: CGPoint
    @State private var scale: CGFloat = 1.5
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .strokeBorder(Color.yellow, lineWidth: 2)
            .frame(width: 80, height: 80)
            .position(point)
            .scaleEffect(scale)
            .opacity(opacity)
            .task {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 1.0
                }
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                }
            }
    }
}

// MARK: - Grid Overlay

struct GridOverlayView: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                // Vertical lines (rule of thirds)
                let width = geometry.size.width
                path.move(to: CGPoint(x: width / 3, y: 0))
                path.addLine(to: CGPoint(x: width / 3, y: geometry.size.height))
                path.move(to: CGPoint(x: width * 2 / 3, y: 0))
                path.addLine(to: CGPoint(x: width * 2 / 3, y: geometry.size.height))

                // Horizontal lines
                let height = geometry.size.height
                path.move(to: CGPoint(x: 0, y: height / 3))
                path.addLine(to: CGPoint(x: width, y: height / 3))
                path.move(to: CGPoint(x: 0, y: height * 2 / 3))
                path.addLine(to: CGPoint(x: width, y: height * 2 / 3))
            }
            .stroke(Color.white.opacity(0.5), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Camera Button Ring

/// White outer ring for the video record button. The record button layers a
/// mode-specific fill (red pill when recording, red circle when idle) on top.
struct CameraButtonRing: View {
    var body: some View {
        Circle()
            .strokeBorder(Color.white, lineWidth: 6)
            .frame(width: 80, height: 80)
    }
}

// MARK: - Camera Settings Sheet

struct CameraSettingsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Video Quality") {
                    Picker("Resolution", selection: $viewModel.settings.quality) {
                        ForEach(RecordingQuality.allCases) { quality in
                            HStack {
                                Image(systemName: quality.systemIcon)
                                Text(quality.displayName)
                            }
                            .tag(quality)
                        }
                    }
                    .pickerStyle(.inline)

                    Text(viewModel.settings.quality.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Frame Rate") {
                    Picker("FPS", selection: $viewModel.settings.frameRate) {
                        ForEach(viewModel.settings.compatibleFrameRates(for: viewModel.settings.quality)) { rate in
                            Text(rate.displayName)
                                .tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(viewModel.settings.frameRate.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Advanced") {
                    Toggle("Slow Motion", isOn: Binding(
                        get: { viewModel.settings.slowMotionEnabled },
                        set: { viewModel.settings.setSlowMotionEnabled($0) }
                    ))
                    .disabled(!viewModel.settings.slowMotionEnabled && !viewModel.settings.supportsSlowMotion)

                    if !viewModel.settings.supportsSlowMotion {
                        Text("Requires 120fps or higher")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Toggle("Audio Recording", isOn: $viewModel.settings.audioEnabled)

                    Picker("Format", selection: $viewModel.settings.format) {
                        ForEach(VideoFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }

                    Text(viewModel.settings.format.description)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Stabilization", selection: $viewModel.settings.stabilizationMode) {
                        ForEach(StabilizationMode.allCases) { mode in
                            Text(mode.displayName)
                                .tag(mode)
                        }
                    }
                }

                Section("Info") {
                    HStack {
                        Text("Per Minute")
                        Spacer()
                        Text("~\(Int(viewModel.settings.estimatedFileSizePerMinute)) MB")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("10 Minutes")
                        Spacer()
                        Text("~\(Int(viewModel.settings.estimatedFileSizePerMinute * 10)) MB")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Camera Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
