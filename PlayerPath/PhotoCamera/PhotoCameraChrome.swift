//
//  PhotoCameraChrome.swift
//  PlayerPath
//
//  Atomic chrome views for the photo camera: shutter, flip, flash, cancel,
//  zoom pills, last-captured thumbnail, focus reticle. Intentionally
//  duplicates small primitives (shutter ring) from the video recorder so
//  photo and video stay fully independent.
//

import SwiftUI
import AVFoundation

// MARK: - Constants

enum PhotoCameraConstants {
    static let buttonSize: CGFloat = 44
    static let shutterOuterSize: CGFloat = 80
    static let shutterInnerSize: CGFloat = 64
    static let shutterRingWidth: CGFloat = 6
    static let zoomPillSize: CGFloat = 34
    static let thumbnailSize: CGFloat = 48
    static let focusReticleSize: CGFloat = 80
    static let focusReticleStrokeWidth: CGFloat = 2
    static let chromeIconFontSize: CGFloat = 18
    /// Background opacity for floating chrome buttons — keeps icons legible
    /// over any preview content (bright outdoor, dark indoor, etc.).
    static let chromeButtonBackgroundOpacity: Double = 0.45
}

// MARK: - Flash Icon Helper

/// File-private: this helper is used only by `PhotoFlashButton` below. Kept
/// at file scope rather than nested inside the button struct so the mapping
/// is easy to find when adding new flash states.
private func photoFlashIconName(_ mode: AVCaptureDevice.FlashMode) -> String {
    switch mode {
    case .on: return "bolt.fill"
    case .auto: return "bolt.badge.automatic"
    default: return "bolt.slash.fill"
    }
}

// MARK: - Chrome Icon Button

/// Floating chrome button with a translucent dark circle background so icons
/// stay legible over any preview content. Used by flash, cancel.
struct PhotoChromeIconButton: View {
    let icon: String
    var highlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: PhotoCameraConstants.chromeIconFontSize, weight: .semibold))
                .foregroundColor(highlighted ? .yellow : .white)
                .frame(width: PhotoCameraConstants.buttonSize,
                       height: PhotoCameraConstants.buttonSize)
                .background(
                    Circle().fill(Color.black.opacity(PhotoCameraConstants.chromeButtonBackgroundOpacity))
                )
                .contentShape(Circle())
        }
    }
}

// MARK: - Shutter

struct PhotoShutterButton: View {
    @ObservedObject var viewModel: PhotoCameraViewModel

    var body: some View {
        Button {
            viewModel.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: PhotoCameraConstants.shutterRingWidth)
                    .frame(width: PhotoCameraConstants.shutterOuterSize,
                           height: PhotoCameraConstants.shutterOuterSize)

                Circle()
                    .fill(Color.white)
                    .frame(width: PhotoCameraConstants.shutterInnerSize,
                           height: PhotoCameraConstants.shutterInnerSize)
                    .scaleEffect(viewModel.isCapturing ? 0.85 : 1.0)
                    .animation(.easeOut(duration: 0.1), value: viewModel.isCapturing)
            }
        }
        .disabled(!viewModel.isSessionReady || viewModel.isCapturing)
        .opacity(viewModel.isSessionReady ? 1 : 0.5)
        .accessibilityLabel("Take Photo")
    }
}

// MARK: - Flip

struct PhotoFlipButton: View {
    @ObservedObject var viewModel: PhotoCameraViewModel

    var body: some View {
        Button {
            viewModel.flipCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: PhotoCameraConstants.buttonSize,
                       height: PhotoCameraConstants.buttonSize)
                .background(
                    Circle().fill(Color.black.opacity(PhotoCameraConstants.chromeButtonBackgroundOpacity))
                )
        }
        .accessibilityLabel("Flip Camera")
    }
}

// MARK: - Flash

struct PhotoFlashButton: View {
    @ObservedObject var viewModel: PhotoCameraViewModel

    var body: some View {
        // Front cameras on iPhone report `supportedFlashModes = [.off]`, so
        // tapping flash on the selfie camera would silently do nothing. Hide
        // the control entirely on front to avoid the misleading tap.
        if viewModel.cameraPosition == .back {
            PhotoChromeIconButton(
                icon: photoFlashIconName(viewModel.flashMode),
                highlighted: viewModel.flashMode == .on,
                action: { viewModel.toggleFlash() }
            )
        }
    }
}

// MARK: - Grid

struct PhotoGridButton: View {
    @ObservedObject var viewModel: PhotoCameraViewModel

    var body: some View {
        PhotoChromeIconButton(
            icon: "square.grid.3x3",
            highlighted: viewModel.showGrid,
            action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showGrid.toggle()
                }
            }
        )
        .accessibilityLabel(viewModel.showGrid ? "Hide Grid" : "Show Grid")
    }
}

// MARK: - Cancel

struct PhotoCancelButton: View {
    let action: () -> Void

    var body: some View {
        PhotoChromeIconButton(icon: "xmark", action: action)
            .accessibilityLabel("Cancel")
    }
}

// MARK: - Zoom Picker

struct PhotoZoomPicker: View {
    @ObservedObject var viewModel: PhotoCameraViewModel
    var vertical: Bool = false

    private var presets: [CGFloat] {
        var values: [CGFloat] = []
        if viewModel.hasUltraWide { values.append(0.5) }
        values.append(1.0)
        values.append(2.0)
        if viewModel.hasTelephoto { values.append(3.0) }
        return values
    }

    private var activePreset: CGFloat? {
        presets.min(by: {
            abs($0 - viewModel.currentZoom) < abs($1 - viewModel.currentZoom)
        })
    }

    var body: some View {
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        let active = activePreset

        layout {
            ForEach(presets, id: \.self) { factor in
                pill(factor, isActive: factor == active)
            }
        }
        .padding(6)
        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.5)))
    }

    private func pill(_ factor: CGFloat, isActive: Bool) -> some View {
        Button {
            viewModel.jumpToZoom(factor)
        } label: {
            Text(label(factor, active: isActive))
                .font(.system(size: isActive ? 13 : 11, weight: .semibold))
                .foregroundColor(isActive ? .yellow : .white)
                .frame(width: PhotoCameraConstants.zoomPillSize,
                       height: PhotoCameraConstants.zoomPillSize)
                .background(
                    Circle().fill(isActive ? Color.black.opacity(0.7) : Color.clear)
                )
                .contentShape(Circle())
        }
    }

    private func label(_ factor: CGFloat, active: Bool) -> String {
        if active {
            let rounded = (viewModel.currentZoom * 10).rounded() / 10
            if rounded == rounded.rounded() {
                return "\(Int(rounded))×"
            }
            return String(format: "%.1f×", rounded)
        }
        if factor < 1 { return ".5" }
        return "\(Int(factor))"
    }
}

// MARK: - Focus Reticle

struct PhotoFocusReticle: View {
    let point: CGPoint
    @State private var scale: CGFloat = 1.5
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .strokeBorder(Color.yellow, lineWidth: PhotoCameraConstants.focusReticleStrokeWidth)
            .frame(width: PhotoCameraConstants.focusReticleSize,
                   height: PhotoCameraConstants.focusReticleSize)
            .position(point)
            .scaleEffect(scale)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) { scale = 1.0 }
                Task {
                    try? await Task.sleep(for: .milliseconds(1500))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
                }
            }
    }
}

// MARK: - Last-Captured Thumbnail

struct PhotoLastThumbnail: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: PhotoCameraConstants.thumbnailSize,
                           height: PhotoCameraConstants.thumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                    )
                    .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear
                    .frame(width: PhotoCameraConstants.thumbnailSize,
                           height: PhotoCameraConstants.thumbnailSize)
            }
        }
    }
}
