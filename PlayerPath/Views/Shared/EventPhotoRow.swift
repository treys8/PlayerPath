//
//  EventPhotoRow.swift
//  PlayerPath
//
//  Shared list row for a photo attached to a game/round or practice — a
//  thumbnail plus caption/date. Used by GameDetailView and PracticeDetailView
//  (extracted from GameDetailView's former private GamePhotoRow).
//

import SwiftUI
import ImageIO

struct EventPhotoRow: View {
    let photo: Photo

    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(photo.caption ?? "Photo")
                    .font(.headingMedium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let date = photo.createdAt {
                    Text(date, style: .date)
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        if let thumbPath = photo.resolvedThumbnailPath {
            if let image = try? await ThumbnailCache.shared.loadThumbnail(at: thumbPath, targetSize: .thumbnailSmall) {
                thumbnail = image
                return
            }
        }
        let path = photo.resolvedFilePath
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let url = URL(fileURLWithPath: path) as CFURL
            guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 150,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
        thumbnail = image
    }
}
