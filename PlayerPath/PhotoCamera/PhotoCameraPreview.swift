//
//  PhotoCameraPreview.swift
//  PlayerPath
//
//  SwiftUI wrapper around `AVCaptureVideoPreviewLayer` for photo mode. Hands
//  the backing layer to the view model once it exists so the VM can install
//  the `RotationCoordinator` and perform accurate tap-to-focus coordinate
//  conversion via `captureDevicePointConverted(fromLayerPoint:)`.
//

import SwiftUI
import AVFoundation

struct PhotoCameraPreview: UIViewRepresentable {
    /// Deliberately plain values rather than an `@ObservedObject` view model.
    /// Observing the view model would re-evaluate this representable on every
    /// `@Published` write — including the per-frame `currentZoom` updates a
    /// pinch produces — dragging `updateUIView` along with it.
    let session: AVCaptureSession
    let onLayerReady: (AVCaptureVideoPreviewLayer) -> Void

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.videoPreviewLayer.session = session
        // `.resizeAspectFill` — full-bleed preview that fills the screen by
        // cropping the sensor's 4:3 frame to match the device aspect. The
        // saved photo is the full 4:3 frame (slightly wider than the visible
        // preview), matching the Instagram/Snapchat full-bleed pattern we
        // committed to in PhotoCameraLayout.
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        // Hand the layer to the view model so it can wire up the rotation
        // coordinator and use `captureDevicePointConverted` for focus.
        onLayerReady(view.videoPreviewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        // Re-set on updates so layer bindings stay in sync across VM resets —
        // but only when they actually differ. The parent layout observes the
        // view model, so this still runs on every published change; assigning
        // `session` unconditionally rebuilds the layer's connection and
        // discards the `videoRotationAngle` the rotation coordinator just set.
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
        if uiView.videoPreviewLayer.videoGravity != .resizeAspectFill {
            uiView.videoPreviewLayer.videoGravity = .resizeAspectFill
        }
    }

    final class PreviewHostView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            guard let layer = layer as? AVCaptureVideoPreviewLayer else {
                fatalError("PreviewHostView.layerClass override missing")
            }
            return layer
        }
    }
}
