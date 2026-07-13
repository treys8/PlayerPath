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
    /// `.fill` = photo crops to fill the screen (no letterbox), `.fit` =
    /// letterboxes to show every pixel. Double-tap toggles between these two;
    /// pinch only adjusts zoom on top.
    @State private var photoContentMode: ContentMode = .fill
    /// Pan offset when zoomed in. Reset to `.zero` any time scale returns to 1×
    /// so the next zoom-in starts centered.
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var isZoomed: Bool { scale > 1.0 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let fullImage {
                // Fill the screen by default (no letterbox). Double-tap toggles
                // fit (see the whole photo, letterboxed) vs fill (cropped). Pinch
                // adjusts zoom from 1× to 5× on top of whichever mode is active.
                // Drag pans when zoomed in.
                GeometryReader { geometry in
                    Image(uiImage: fullImage)
                        .resizable()
                        .aspectRatio(contentMode: photoContentMode)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(5.0, max(1.0, lastScale * value))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale == 1.0 {
                                        // Zoomed back to default — drop any pan
                                        // so the next zoom starts centered.
                                        withAnimation(.spring(response: 0.3)) {
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
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
                                    offset = clampOffset(proposed, scale: scale, in: geometry.size)
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                },
                            including: isZoomed ? .gesture : .subviews
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if isZoomed {
                                    // Zoomed in → reset to default zoom + pan.
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    // At default zoom → toggle fit/fill.
                                    photoContentMode = photoContentMode == .fill ? .fit : .fill
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
    /// dragged past the corresponding screen edges. The extra-per-side is
    /// `(scale - 1) * viewport / 2` in each dimension, assuming the image's
    /// base size at scale 1× is at least the viewport (true for `.fill`; for
    /// `.fit` the bound is tighter but this cap is safe and intuitive).
    private func clampOffset(_ proposed: CGSize, scale: CGFloat, in viewport: CGSize) -> CGSize {
        let maxX = max(0, (scale - 1) * viewport.width / 2)
        let maxY = max(0, (scale - 1) * viewport.height / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    private func loadFullImage() async {
        // Skip if already loaded (page can reappear after scrolling back).
        if fullImage != nil { return }

        // `Photo` is a non-Sendable @Model — snapshot the paths on the main actor,
        // then decode the (potentially 12MP) image off-main via `Task.detached`.
        let filePath = photo.resolvedFilePath
        let cloudURL = photo.cloudURL

        if let image = await UIImage.decodedFullRes(atPath: filePath) {
            fullImage = image
            return
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
