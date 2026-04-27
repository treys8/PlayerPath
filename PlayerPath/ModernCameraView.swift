//
//  ModernCameraView.swift
//  PlayerPath
//
//  Created by Assistant on 12/25/25.
//  SwiftUI video recorder with full AVFoundation control.
//  Photo capture lives in native iOS Camera via `ImagePicker(sourceType: .camera)`.
//

import SwiftUI
import AVFoundation

// MARK: - Modern Camera View

/// Full-screen video recorder with tap-to-focus, pinch-to-zoom, and professional
/// controls (resolution, frame rate, slow-mo, stabilization, codec, flash torch).
/// Photos flow through `UIImagePickerController` and do not touch this view.
struct ModernCameraView: View {
    @StateObject private var viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let onVideoRecorded: (URL) -> Void
    let onCancel: () -> Void
    let onError: ((Error) -> Void)?

    @State private var showingSettings = false
    // Frozen landscape flag while recording so controls don't rearrange mid-take.
    @State private var recordingLandscape: Bool? = nil
    // Frozen device orientation while recording. The capture connection's orientation
    // is locked at startRecording() in CameraViewModel, so if the user rotates mid-take
    // the preview layer would diverge from the recorded frames. Freezing the preview
    // to the record-start orientation keeps preview and file aligned.
    @State private var recordingOrientation: UIDeviceOrientation? = nil

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

    var body: some View {
        GeometryReader { geometry in
        // Landscape is decided from actual view geometry (synchronous with
        // window rotation) rather than UIDevice orientation notifications
        // (async, can lag by a frame). `recordingLandscape` freezes the flag
        // during a take so controls don't shift mid-record.
        let landscape = recordingLandscape ?? (geometry.size.width > geometry.size.height)

        ZStack {
            // Camera Preview Layer
            CameraPreviewLayer(
                session: viewModel.captureSession,
                orientation: recordingOrientation ?? viewModel.currentOrientation,
                gravity: .resizeAspectFill
            )
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
            if landscape {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: landscape)
        .onChange(of: viewModel.isRecording) { _, isRecording in
            if isRecording {
                recordingLandscape = geometry.size.width > geometry.size.height
                recordingOrientation = viewModel.currentOrientation
            } else {
                recordingLandscape = nil
                recordingOrientation = nil
            }
        }
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
        .accessibilityLabel(viewModel.isRecording ? "Stop recording to cancel" : "Cancel")
        .help(viewModel.isRecording ? "Stop recording first" : "Cancel")
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
                CameraButtonRing()

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
            .font(.custom("Inter18pt-SemiBold", size: 11, relativeTo: .caption2))
            .monospacedDigit()
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
            .font(.labelSmall)
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

// `CameraPreviewLayer`, `FocusReticleView`, `GridOverlayView`, `CameraButtonRing`,
// and `CameraSettingsView` live in `CameraComponents.swift`.

// MARK: - Preview

#Preview {
    ModernCameraView(
        onVideoRecorded: { _ in },
        onCancel: { }
    )
}
