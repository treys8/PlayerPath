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
    @ObservedObject var viewModel: PhotoCameraViewModel

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.videoPreviewLayer.session = viewModel.captureSession
        // `.resizeAspectFill` — full-bleed preview that fills the screen by
        // cropping the sensor's 4:3 frame to match the device aspect. The
        // saved photo is the full 4:3 frame (slightly wider than the visible
        // preview), matching the Instagram/Snapchat full-bleed pattern we
        // committed to in PhotoCameraLayout.
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        // Hand the layer to the view model so it can wire up the rotation
        // coordinator and use `captureDevicePointConverted` for focus.
        viewModel.previewLayer = view.videoPreviewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        // Re-set on updates so layer bindings stay in sync across VM resets.
        uiView.videoPreviewLayer.session = viewModel.captureSession
        uiView.videoPreviewLayer.videoGravity = .resizeAspectFill
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
