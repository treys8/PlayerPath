//
//  ModernCameraView.swift
//  PlayerPath
//
//  Created by Assistant on 12/25/25.
//  Modern SwiftUI camera with full AVFoundation control
//

import SwiftUI
import AVFoundation

// MARK: - Modern Camera View

/// Modern full-screen camera view with tap-to-focus, pinch-to-zoom, and professional controls
struct ModernCameraView: View {
    @StateObject private var viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let onVideoRecorded: (URL) -> Void
    let onCancel: () -> Void
    let onError: ((Error) -> Void)?

    @State private var showingSettings = false
    @State private var showingTutorial = false
    @State private var dragOffset: CGFloat = 0

    @MainActor
    init(
        settings: VideoRecordingSettings? = nil,
        onVideoRecorded: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void,
        onError: ((Error) -> Void)? = nil
    ) {
        let effectiveSettings = settings ?? VideoRecordingSettings.shared
        self._viewModel = StateObject(wrappedValue: CameraViewModel(settings: effectiveSettings))
        self.onVideoRecorded = onVideoRecorded
        self.onCancel = onCancel
        self.onError = onError
    }

    // MARK: - Orientation

    private var isLandscape: Bool {
        viewModel.currentOrientation == .landscapeLeft || viewModel.currentOrientation == .landscapeRight
    }

    var body: some View {
        GeometryReader { geometry in
        ZStack {
            // Camera Preview Layer
            CameraPreviewLayer(session: viewModel.captureSession, orientation: viewModel.currentOrientation)
                .ignoresSafeArea()
                .opacity(viewModel.isSessionReady ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isSessionReady)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            viewModel.handleTapToFocus(at: value.location, viewSize: geometry.size)
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            viewModel.handleZoom(scale: value.magnification)
                        }
                        .onEnded { _ in
                            viewModel.endZoomGesture()
                        }
                )

            // Focus Reticle
            if let focusPoint = viewModel.lastFocusPoint {
                FocusReticleView(point: focusPoint)
                    .id("\(focusPoint.x),\(focusPoint.y)")
                    .transition(.scale.combined(with: .opacity))
            }

            // Grid Overlay
            if viewModel.showGrid {
                GridOverlayView()
                    .transition(.opacity)
            }

            // Camera Controls Overlay
            if isLandscape {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isLandscape)
        .statusBar(hidden: true)
        .onDisappear {
            viewModel.stopSession()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.stopSession()
            } else if newPhase == .active {
                Task { await viewModel.startSession() }
            }
        }
        .alert("Camera Error", isPresented: $viewModel.showingError) {
            if viewModel.errorNeedsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    if viewModel.isFatalError {
                        onCancel()
                    }
                }
                Button("Cancel", role: .cancel) {
                    if viewModel.isFatalError {
                        onCancel()
                    }
                }
            } else {
                Button("OK", role: .cancel) {
                    if viewModel.isFatalError {
                        onCancel()
                    }
                }
            }
        } message: {
            if let error = viewModel.currentError {
                Text(error)
            }
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            viewModel.reconfigureSession()
        }) {
            CameraSettingsView(viewModel: viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: viewModel.recordedVideoURL) { _, newURL in
            if let url = newURL {
                onVideoRecorded(url)
            }
        }
        } // GeometryReader
    }

    // MARK: - Atomic Controls

    private var cancelButton: some View {
        Button {
            Haptics.light()
            onCancel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
        }
        .disabled(viewModel.isRecording)
        .opacity(viewModel.isRecording ? 0.5 : 1)
    }

    @ViewBuilder
    private var recordingTimerBadge: some View {
        if viewModel.isRecording {
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .opacity(viewModel.recordingPulse ? 0.3 : 1.0)

                Text(viewModel.recordingTimeString)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.black.opacity(0.6))
            )
        }
    }

    @ViewBuilder
    private var slowMoBadge: some View {
        if viewModel.settings.slowMotionEnabled {
            Text("SLOW-MO")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.purple)
                )
        }
    }

    private var flashButton: some View {
        Button {
            Haptics.light()
            viewModel.toggleFlash()
        } label: {
            Image(systemName: viewModel.flashMode == .on ? "bolt.fill" : viewModel.flashMode == .auto ? "bolt.badge.automatic" : "bolt.slash.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(viewModel.flashMode == .on ? .yellow : .white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
        }
        .disabled(viewModel.isRecording)
        .opacity(viewModel.isRecording ? 0.5 : 1)
    }

    private var flipButton: some View {
        Button {
            Haptics.medium()
            viewModel.flipCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
        }
        .disabled(viewModel.isRecording)
        .opacity(viewModel.isRecording ? 0.5 : 1)
    }

    private var gridButton: some View {
        Button {
            Haptics.light()
            withAnimation {
                viewModel.showGrid.toggle()
            }
        } label: {
            Image(systemName: viewModel.showGrid ? "grid.circle.fill" : "grid.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
        }
    }

    private var settingsButton: some View {
        Button {
            Haptics.light()
            showingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
        }
        .disabled(viewModel.isRecording)
        .opacity(viewModel.isRecording ? 0.5 : 1)
    }

    private var recordButton: some View {
        Button {
            Haptics.heavy()
            if viewModel.isRecording {
                viewModel.stopRecording()
            } else {
                viewModel.startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 6)
                    .frame(width: 80, height: 80)

                RoundedRectangle(cornerRadius: viewModel.isRecording ? 8 : 40)
                    .fill(Color.red)
                    .frame(width: viewModel.isRecording ? 40 : 64,
                           height: viewModel.isRecording ? 40 : 64)
            }
        }
        .disabled(!viewModel.isSessionReady)
        .opacity(viewModel.isSessionReady ? 1 : 0.5)
    }

    private var zoomBadge: some View {
        Text(String(format: "%.1f×", viewModel.currentZoom))
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
    }

    private var qualityText: some View {
        Text(viewModel.settings.settingsDescription)
            .font(.caption2)
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.black.opacity(0.35))
            )
    }

    // MARK: - Portrait Layout

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            // Top Controls
            ZStack(alignment: .top) {
                // Center: recording timer
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        recordingTimerBadge
                        slowMoBadge
                    }
                    Spacer()
                }

                // Left: cancel button
                HStack {
                    cancelButton
                    Spacer()
                }

                // Right: utility buttons
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        flashButton
                        flipButton
                        gridButton
                        settingsButton
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            // Bottom Controls
            VStack(spacing: 16) {
                zoomBadge

                recordButton
                qualityText
            }
            .padding(.bottom, 40)
        }
        .animation(.spring(response: 0.3), value: viewModel.isRecording)
    }

    // MARK: - Landscape Layout

    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            // Left column: cancel at top, status badges below, utility buttons at bottom
            VStack(spacing: 12) {
                cancelButton

                // Timer + slow-mo badge below cancel in landscape
                VStack(spacing: 6) {
                    recordingTimerBadge
                    slowMoBadge
                }

                Spacer()

                flashButton
                flipButton
                gridButton
                settingsButton
            }
            .padding(.leading, 20)
            .padding(.vertical, 16)

            Spacer()

            // Right column: quality text top, record button centered, zoom above it
            VStack(spacing: 12) {
                qualityText

                Spacer()

                zoomBadge
                recordButton

                Spacer()
            }
            .padding(.trailing, 12)
            .padding(.vertical, 16)
        }
        .animation(.spring(response: 0.3), value: viewModel.isRecording)
    }
}

// MARK: - Camera Preview Layer

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    let orientation: UIDeviceOrientation

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        updatePreviewOrientation(view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        updatePreviewOrientation(uiView)
    }

    private func updatePreviewOrientation(_ view: PreviewView) {
        guard let connection = view.videoPreviewLayer.connection else { return }

        if #available(iOS 17.0, *) {
            let angle: CGFloat = switch orientation {
            case .landscapeLeft: 0
            case .landscapeRight: 180
            case .portraitUpsideDown: 270
            default: 90
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else {
            let videoOrientation: AVCaptureVideoOrientation = switch orientation {
            case .landscapeLeft: .landscapeRight
            case .landscapeRight: .landscapeLeft
            case .portraitUpsideDown: .portraitUpsideDown
            default: .portrait
            }
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = videoOrientation
            }
        }
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
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 1.0
                }

                Task {
                    try? await Task.sleep(for: .milliseconds(1500))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        opacity = 0
                    }
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

// MARK: - Preview

#Preview {
    ModernCameraView(
        onVideoRecorded: { url in
        },
        onCancel: {
        }
    )
}
