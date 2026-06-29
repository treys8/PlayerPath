//
//  JournalPhotoThumbnail.swift
//  PlayerPath
//
//  Fills a PPMediaTile's content slot with a standalone photo's thumbnail for
//  the Journal feed. Loads asynchronously via the shared PhotoThumbnailLoader;
//  while loading (or if the image is unavailable) it shows a muted glyph over
//  the tile color. When the photo is cloud-backed but not yet downloaded, the
//  failed-state glyph becomes an iCloud-download hint — mirroring
//  PhotoThumbnailCell so a not-downloaded photo reads as "tap to get it", not
//  "broken". Sizing mirrors VideoThumbnailView(fillsContainer:).
//

import SwiftUI

struct JournalPhotoThumbnail: View {
    let photo: Photo

    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image {
                // minWidth/minHeight 0 is load-bearing: without them the
                // resizable image's intrinsic size leaks into layout and the
                // enclosing PPMediaTile's .aspectRatio(.fill) grows unbounded
                // instead of clamping to 16:9 (matches VideoThumbnailView).
                // alignment: .top anchors the fill to the top so a portrait
                // photo overflowing the wide 16:9 box is cropped from the
                // bottom — preserving heads/subjects instead of center-slicing.
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                Image(systemName: fallbackGlyph)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: photo.id) {
            loadFailed = false
            if let loaded = await PhotoThumbnailLoader.load(for: photo) {
                image = loaded
            } else {
                loadFailed = true
            }
        }
    }

    /// Plain photo glyph while loading or when truly missing; an iCloud-download
    /// hint when the load failed but the photo is backed by a cloud copy.
    private var fallbackGlyph: String {
        if loadFailed, let url = photo.cloudURL, !url.isEmpty {
            return "icloud.and.arrow.down"
        }
        return "photo"
    }
}
