//
//  ScorecardScannerView.swift
//  PlayerPath
//
//  Thin SwiftUI wrapper over VisionKit's VNDocumentCameraViewController — the
//  same document scanner used by Notes/Files, so the captured scorecard comes
//  back deskewed and perspective-corrected for free. We take page 0 only (one
//  card per scan); the resulting UIImage rides the EXISTING Photo persistence +
//  upload path (flagged isScorecardPhoto) and is OCR'd locally, so capture works
//  offline. No new Info.plist key needed — NSCameraUsageDescription already ships.
//

import SwiftUI
import VisionKit

struct ScorecardScannerView: UIViewControllerRepresentable {
    /// Delivers the deskewed first page. Called on the main thread.
    let onScan: (UIImage) -> Void
    /// Cancelled or failed — dismiss without a result.
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onScan: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // One card per scan — take the first page only.
            guard scan.pageCount > 0 else {
                onCancel()
                return
            }
            let image = scan.imageOfPage(at: 0)
            onScan(image)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onCancel()
        }
    }
}
