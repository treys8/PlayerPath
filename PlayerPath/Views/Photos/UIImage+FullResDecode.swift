//
//  UIImage+FullResDecode.swift
//  PlayerPath
//
//  Shared off-main full-resolution decode used by the full-screen photo viewer
//  (ZoomablePhotoPage for display, PhotoDetailView for Save-to-Camera-Roll).
//

import UIKit

extension UIImage {
    /// Decodes a (potentially 12MP) image file off the main thread via
    /// `Task.detached` — the codebase's established off-main convention. The
    /// caller assigns the result on the main actor.
    static func decodedFullRes(atPath path: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: path)
        }.value
    }
}
