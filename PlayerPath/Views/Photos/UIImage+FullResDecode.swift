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
    ///
    /// `UIImage(contentsOfFile:)` alone only maps the file — the JPEG decode
    /// would then run on the MAIN thread at first draw, right as the page
    /// swipes in (a visible hitch). `preparingForDisplay()` forces the decode
    /// here instead. It returns nil for images it can't prepare, so fall back
    /// to the lazy image rather than failing the load.
    static func decodedFullRes(atPath path: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(contentsOfFile: path) else { return nil }
            return image.preparingForDisplay() ?? image
        }.value
    }
}
