//
//  ZoomablePhotoPage.swift
//  PlayerPath
//
//  A single zoomable/pannable photo, used as one page inside PhotoDetailView's
//  swipeable pager. Owns only the image + gesture state (it's the one place that
//  knows the current zoom `scale`); all chrome (toolbar, metadata, sheets) and
//  the reaction to reported gestures live in the PhotoDetailView container so
//  they render once no matter how many pages are loaded.
//

import SwiftUI

struct ZoomablePhotoPage: View {
    let photo: Photo
    /// Reports whether this page is currently zoomed in (>1×) so the container
    /// can hide its metadata overlay. Only the on-screen page emits changes.
    var onZoomChanged: (Bool) -> Void = { _ in }
    /// Single tap (not a zoom double-tap) — container toggles chrome visibility.
    var onSingleTap: () -> Void = { }

    @State private var fullImage: UIImage?
    @State private var loadFailed = false
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    /// Pan offset when zoomed in. Reset to `.zero` any time scale returns to 1×
    /// so the next zoom-in starts centered.
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    /// Double-tap zooms the tapped point to this scale (Photos.app convention).
    private static let doubleTapScale: CGFloat = 2.5
    private static let maxScale: CGFloat = 5.0

    private var isZoomed: Bool { scale > 1.0 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let fullImage {
                // Aspect-FIT by default so the whole photo is visible, like
                // Photos.app. The old `.fill` default cropped ~65% of a landscape
                // shot on a portrait phone, and pinch can't zoom out below 1× to
                // recover it. Pinch zooms 1×–5×; double-tap zooms to the tapped
                // point; drag pans only while zoomed.
                GeometryReader { geometry in
                    Image(uiImage: fullImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scale = min(Self.maxScale, max(1.0, lastScale * value.magnification))
                                    // Zooming out shrinks the pannable area — pull the
                                    // pan back inside it so an image edge never
                                    // detaches from the screen edge mid-pinch.
                                    offset = clampOffset(lastOffset, scale: scale, imageSize: fullImage.size, in: geometry.size)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale == 1.0 {
                                        // Zoomed back to default — drop any pan
                                        // so the next zoom starts centered.
                                        withAnimation(.spring(response: 0.3)) {
                                            offset = .zero
                                        }
                                    }
                                    lastOffset = offset
                                    onZoomChanged(isZoomed)
                                }
                        )
                        // When zoomed, this drag pans the photo instead of flipping
                        // pages. The `including:` mask must fully disable it at 1×:
                        // ANY drag recognizer attached here — even a .simultaneousGesture
                        // that ignores the touch — starves the TabView pager of
                        // horizontal drags (and the zoom transition of its dismiss
                        // pan), which is exactly the "can't swipe to next photo" bug.
                        // Swipe-down-to-dismiss is NOT reimplemented here for the
                        // same reason; the iOS 18 zoom transition provides it.
                        .highPriorityGesture(
                            DragGesture()
                                .onChanged { value in
                                    guard isZoomed else { return }
                                    let proposed = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                    offset = clampOffset(proposed, scale: scale, imageSize: fullImage.size, in: geometry.size)
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                },
                            including: isZoomed ? .gesture : .subviews
                        )
                        .onTapGesture(count: 2) { location in
                            withAnimation(.spring(response: 0.3)) {
                                if isZoomed {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    zoom(to: Self.doubleTapScale, at: location, imageSize: fullImage.size, in: geometry.size)
                                }
                            }
                            onZoomChanged(isZoomed)
                        }
                        // Declared after the double-tap so the count:2 recognizer
                        // wins the ambiguity; a lone tap toggles chrome.
                        .onTapGesture(count: 1) {
                            onSingleTap()
                        }
                }
            } else if loadFailed {
                VStack(spacing: 8) {
                    Image(systemName: photo.cloudURL != nil ? "icloud.and.arrow.down" : "photo")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.5))
                    Text(photo.cloudURL != nil ? "Photo not yet downloaded" : "Photo unavailable")
                        .font(.bodyMedium)
                        .foregroundColor(.white.opacity(0.5))
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task {
            await loadFullImage()
        }
        .onDisappear {
            // Release the (potentially 12MP) decode when this page scrolls out of
            // the pager so only near pages hold a full-res image.
            fullImage = nil
        }
    }

    /// Clamps a proposed pan offset so the zoomed image's edges can't be
    /// dragged past the screen edges. Works from the image's aspect-FIT size in
    /// `viewport`, so an axis where the zoomed image is still narrower than the
    /// screen (e.g. the height of a landscape shot at 2.5×) gets no pan at all.
    private func clampOffset(_ proposed: CGSize, scale: CGFloat, imageSize: CGSize, in viewport: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let fitRatio = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let maxX = max(0, (imageSize.width * fitRatio * scale - viewport.width) / 2)
        let maxY = max(0, (imageSize.height * fitRatio * scale - viewport.height) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    /// Zooms to `target` keeping the tapped point under the finger.
    /// `scaleEffect` scales about the view's center `c`, sending a point `p` to
    /// `c + s·(p − c)`; offsetting by `(1 − s)·(p − c)` puts it back at `p`.
    /// The clamp then pulls a tap in the letterbox band onto the image edge.
    private func zoom(to target: CGFloat, at location: CGPoint, imageSize: CGSize, in viewport: CGSize) {
        let proposed = CGSize(
            width: (1 - target) * (location.x - viewport.width / 2),
            height: (1 - target) * (location.y - viewport.height / 2)
        )
        scale = target
        lastScale = target
        offset = clampOffset(proposed, scale: target, imageSize: imageSize, in: viewport)
        lastOffset = offset
    }

    private func loadFullImage() async {
        // Skip if already loaded (page can reappear after scrolling back).
        if fullImage != nil { return }

        // `Photo` is a non-Sendable @Model — snapshot the paths on the main actor,
        // then decode the (potentially 12MP) image off-main via `Task.detached`.
        let filePath = photo.resolvedFilePath
        let cloudURL = photo.cloudURL
        let fileName = photo.fileName

        if let image = await UIImage.decodedFullRes(atPath: filePath) {
            fullImage = image
            return
        }
        // Signed URL first — short-lived, ownership re-derived server-side from the ID token.
        // `cloudURL` below is the legacy permanent downloadURL() token (no auth, bypasses
        // storage.rules, never expires) and stays only as a fallback until those tokens are
        // rotated. See SecureURLManager.getPersonalPhotoURL.
        if !fileName.isEmpty {
            do {
                let signed = try await SecureURLManager.shared.getPersonalPhotoURL(fileName: fileName)
                try await VideoCloudManager.shared.downloadPhoto(from: signed, to: filePath)
                if let image = await UIImage.decodedFullRes(atPath: filePath) {
                    fullImage = image
                    return
                }
            } catch {
                // Fall through to the legacy token URL below.
            }
        }
        // If local file is missing but we have a cloud URL, try downloading.
        if let cloudURL, !cloudURL.isEmpty {
            do {
                try await VideoCloudManager.shared.downloadPhoto(from: cloudURL, to: filePath)
                if let image = await UIImage.decodedFullRes(atPath: filePath) {
                    fullImage = image
                    return
                }
            } catch {
                ErrorHandlerService.shared.handle(error, context: "ZoomablePhotoPage.downloadPhoto", showAlert: false)
            }
        }
        loadFailed = true
    }
}
