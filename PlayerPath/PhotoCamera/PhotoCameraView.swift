//
//  PhotoCameraView.swift
//  PlayerPath
//
//  Entry point for the photo camera. Presented via `fullScreenCover` from
//  PhotosView, GameDetailView, and ProfileImageManager. Captures a UIImage
//  via `onPhotoCaptured` and dismisses. Independent of the video recorder.
//

import SwiftUI
import AVFoundation

struct PhotoCameraView: View {
    @StateObject private var viewModel = PhotoCameraViewModel()
    @Environment(\.scenePhase) private var scenePhase

    let onPhotoCaptured: (UIImage) -> Void
    let onCancel: () -> Void

    // Shutter flash overlay (white wash 0 → 0.85 → 0) — matches the native
    // iOS Camera feel. Scoped to this view so the view model stays pure.
    @State private var shutterFlashOpacity: Double = 0
    // Last-captured thumbnail displayed briefly in the shutter row. The
    // thumbnail is visible during the fullScreenCover's ~350ms dismissal
    // animation after the consumer receives the photo and closes the sheet.
    @State private var lastThumbnail: UIImage? = nil

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                PhotoCameraLayout(
                    viewModel: viewModel,
                    landscape: landscape,
                    lastThumbnail: lastThumbnail,
                    onCancel: onCancel
                )

                Color.white
                    .opacity(shutterFlashOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: landscape)
        }
        .statusBar(hidden: true)
        .onChange(of: viewModel.capturedImage) { _, newImage in
            guard let image = newImage else { return }

            // Brief white flash — tactile feedback for the shutter tap. Runs
            // concurrently with delivery; the consumer dismisses on delivery
            // and the fullScreenCover's ~350ms dismissal animation plays out
            // over the flash and thumbnail, so the user sees both before the
            // sheet is gone.
            withAnimation(.easeOut(duration: 0.08)) { shutterFlashOpacity = 0.85 }
            Task {
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.easeIn(duration: 0.15)) { shutterFlashOpacity = 0 }
            }

            withAnimation(.easeOut(duration: 0.2)) {
                lastThumbnail = image
            }

            // Deliver immediately — the audit found that a delayed delivery
            // could silently drop the photo if the sheet dismissed inside the
            // delay window (background event, rapid cancel). Synchronous
            // delivery means the photo is always handed off the moment it's
            // available; the thumbnail visual rides the dismissal animation.
            onPhotoCaptured(image)
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Only stop on `.background` — `.inactive` fires for momentary
            // transitions like alert presentation or notification banners,
            // and tearing down the session there causes the preview to flicker.
            switch newPhase {
            case .background:
                viewModel.stop()
            case .active:
                Task { await viewModel.start() }
            default:
                break
            }
        }
        .alert("Camera Error", isPresented: $viewModel.showingError) {
            if viewModel.errorNeedsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    if viewModel.isFatalError { onCancel() }
                }
                Button("Cancel", role: .cancel) {
                    if viewModel.isFatalError { onCancel() }
                }
            } else {
                Button("OK", role: .cancel) {
                    if viewModel.isFatalError { onCancel() }
                }
            }
        } message: {
            if let error = viewModel.currentError {
                Text(error)
            }
        }
    }
}

// MARK: - Camera Availability

enum PhotoCameraAvailability {
    /// AVFoundation-native camera availability check. Replaces the
    /// `UIImagePickerController.isSourceTypeAvailable(.camera)` check used by
    /// the ImagePicker migration — same semantic, no UIKit dependency.
    static var isCameraAvailable: Bool {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.isEmpty == false
    }
}

#Preview {
    PhotoCameraView(
        onPhotoCaptured: { _ in },
        onCancel: { }
    )
}
