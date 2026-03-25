//
//  PhotoThumbnailCell.swift
//  PlayerPath
//
//  Square thumbnail cell for the photos grid.
//

import SwiftUI
import ImageIO

struct PhotoThumbnailCell: View {
    let photo: Photo
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?
    @State private var loadFailed = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else if loadFailed {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: photo.cloudURL != nil ? "icloud.and.arrow.down" : "photo")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            if photo.cloudURL != nil {
                                Text("Syncing…")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        ProgressView()
                    }
            }

            // Badge if tagged to game or practice
            if photo.game != nil || photo.practice != nil {
                HStack(spacing: 3) {
                    Image(systemName: photo.game != nil ? "baseball.diamond.bases" : "figure.run")
                        .font(.system(size: 8))
                    if let game = photo.game {
                        Text(game.opponent)
                            .font(.system(size: 8))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.6)))
                .padding(4)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Photo", systemImage: "trash")
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        if let thumbPath = photo.resolvedThumbnailPath {
            if let image = try? await ThumbnailCache.shared.loadThumbnail(at: thumbPath) {
                thumbnail = image
                return
            }
        }
        // Fallback: load a downsampled version instead of the full-res bitmap
        let url = URL(fileURLWithPath: photo.resolvedFilePath) as CFURL
        if let source = CGImageSourceCreateWithURL(url, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 300,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                thumbnail = UIImage(cgImage: cgImage)
                return
            }
        }
        // If we have a cloud URL but no local file, attempt to download it
        if let cloudURL = photo.cloudURL, !cloudURL.isEmpty {
            do {
                try await VideoCloudManager.shared.downloadPhoto(from: cloudURL, to: photo.resolvedFilePath)
                // Retry loading after download
                let downloadedURL = URL(fileURLWithPath: photo.resolvedFilePath) as CFURL
                if let source = CGImageSourceCreateWithURL(downloadedURL, nil) {
                    let options: [CFString: Any] = [
                        kCGImageSourceThumbnailMaxPixelSize: 300,
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true
                    ]
                    if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                        thumbnail = UIImage(cgImage: cgImage)
                        return
                    }
                }
            } catch {
                // Download failed — fall through to loadFailed
            }
        }
        loadFailed = true
    }
}
