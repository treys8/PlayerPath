//
//  PhotoThumbnailCell.swift
//  PlayerPath
//
//  Square thumbnail cell for the photos grid.
//

import SwiftUI

struct PhotoThumbnailCell: View {
    let photo: Photo
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
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
                    Image(systemName: photo.game != nil ? "sportscourt.fill" : "figure.run")
                        .font(.system(size: 8))
                    if let game = photo.game {
                        Text(game.opponent)
                            .font(.system(size: 8))
                            .lineLimit(1)
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
        if let thumbPath = photo.thumbnailPath {
            if let image = try? await ThumbnailCache.shared.loadThumbnail(at: thumbPath) {
                thumbnail = image
                return
            }
        }
        // Fallback to full image
        if let image = UIImage(contentsOfFile: photo.filePath) {
            thumbnail = image
        }
    }
}
