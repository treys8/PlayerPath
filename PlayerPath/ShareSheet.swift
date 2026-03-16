//
//  ShareSheet.swift
//  PlayerPath
//
//  UIKit share sheet wrapper for SwiftUI
//

import SwiftUI
import UIKit

/// SwiftUI wrapper for UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil
    /// When true, any file URLs in `items` are deleted after the share sheet is dismissed.
    var cleanupFilesOnDismiss: Bool = true

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = excludedActivityTypes

        if cleanupFilesOnDismiss {
            let fileURLs = items.compactMap { $0 as? URL }.filter { $0.isFileURL }
            controller.completionWithItemsHandler = { _, _, _, _ in
                for url in fileURLs {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}
