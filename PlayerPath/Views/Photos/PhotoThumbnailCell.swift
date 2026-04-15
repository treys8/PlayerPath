//
//  PhotoThumbnailCell.swift
//  PlayerPath
//
//  Card-style photo cell with thumbnail and info section.
//

import SwiftUI
import SwiftData
import ImageIO

struct PhotoThumbnailCell: View {
    @Bindable var photo: Photo
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?
    @State private var loadFailed = false
    @State private var showingTagSheet = false
    @State private var showingCaptionSheet = false
    @State private var captionText: String = ""
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
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
            }
            .aspectRatio(3.0/4.0, contentMode: .fill)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12))

            // Info section
            VStack(alignment: .leading, spacing: 4) {
                if let caption = photo.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 4) {
                    if let game = photo.game {
                        Text("vs \(game.opponent)")
                            .font(.caption)
                            .foregroundColor(.brandNavy)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else if photo.practice != nil {
                        Text("Practice")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Spacer()

                    if let date = photo.createdAt {
                        Text(date, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .contextMenu {
            if photo.isAvailableOffline, let url = photo.fileURL {
                ShareLink(
                    item: url,
                    preview: SharePreview(
                        photo.caption ?? "Photo",
                        image: thumbnail.map { Image(uiImage: $0) } ?? Image(systemName: "photo")
                    )
                ) {
                    Label("Share Photo", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                showingTagSheet = true
            } label: {
                Label("Tag to Game/Practice", systemImage: "tag")
            }

            Button {
                captionText = photo.caption ?? ""
                showingCaptionSheet = true
            } label: {
                Label(photo.caption != nil ? "Edit Caption" : "Add Caption", systemImage: "text.bubble")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Photo", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingTagSheet) {
            PhotoTagSheet(photo: photo)
        }
        .sheet(isPresented: $showingCaptionSheet) {
            CaptionEditSheet(captionText: $captionText) {
                photo.caption = captionText.isEmpty ? nil : captionText
                photo.needsSync = true
                ErrorHandlerService.shared.saveContext(modelContext, caller: "PhotoThumbnailCell.saveCaption")
            }
            .presentationDetents([.medium])
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        // Decode an aspect-preserving thumbnail from the full-resolution photo via
        // CGImageSource. We intentionally skip the pre-cached thumbnail file because
        // legacy thumbnails are 300x300 square crops (heads chopped) generated before
        // the 3:4 grid redesign.
        let url = URL(fileURLWithPath: photo.resolvedFilePath) as CFURL
        if let source = CGImageSourceCreateWithURL(url, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 600,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                thumbnail = UIImage(cgImage: cgImage)
                return
            }
        }
        if let cloudURL = photo.cloudURL, !cloudURL.isEmpty {
            do {
                try await VideoCloudManager.shared.downloadPhoto(from: cloudURL, to: photo.resolvedFilePath)
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
                // Download failed
            }
        }
        loadFailed = true
    }
}
