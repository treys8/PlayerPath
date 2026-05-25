//
//  PhotoHeroCell.swift
//  PlayerPath
//
//  Magazine-style "Most Recent" hero rendered above the grid in PhotosView when
//  no filters are active. Sizes to the photo's aspect ratio (capped), gradient
//  scrim with caption, context menu parity with PhotoThumbnailCell.
//

import SwiftUI
import SwiftData

private struct HeroWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PhotoHeroCell: View {
    @Bindable var photo: Photo
    let onDelete: () -> Void
    var onContextMenuOpened: (() -> Void)? = nil

    @State private var thumbnail: UIImage?
    @State private var imageAspectRatio: CGFloat?
    @State private var containerWidth: CGFloat = 0
    @State private var loadFailed = false
    @State private var showingTagSheet = false
    @State private var showingCaptionSheet = false
    @State private var captionText: String = ""
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var maxHeroHeight: CGFloat {
        horizontalSizeClass == .regular ? 560 : 460
    }

    private var fallbackHeroHeight: CGFloat {
        horizontalSizeClass == .regular ? 380 : 240
    }

    private var heroHeight: CGFloat {
        guard let imageAspectRatio, containerWidth > 0 else {
            return fallbackHeroHeight
        }
        return min(containerWidth / imageAspectRatio, maxHeroHeight)
    }

    var body: some View {
        ZStack {
            imageLayer

            recentPill
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)

            if let icon = syncIndicatorIcon {
                syncBadge(icon: icon.name, color: icon.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(12)
            }

            bottomScrim
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: heroHeight)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HeroWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(HeroWidthPreferenceKey.self) { containerWidth = $0 }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .contextMenu {
            Group {
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
                Button { showingTagSheet = true } label: {
                    Label("Tag to Game/Practice", systemImage: "tag")
                }
                Button {
                    captionText = photo.caption ?? ""
                    showingCaptionSheet = true
                } label: {
                    Label(photo.caption != nil ? "Edit Caption" : "Add Caption", systemImage: "text.bubble")
                }
                Divider()
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete Photo", systemImage: "trash")
                }
            }
            .onAppear { onContextMenuOpened?() }
        }
        .sheet(isPresented: $showingTagSheet) {
            PhotoTagSheet(photo: photo)
        }
        .sheet(isPresented: $showingCaptionSheet) {
            CaptionEditSheet(captionText: $captionText) {
                photo.caption = captionText.isEmpty ? nil : captionText
                photo.needsSync = true
                ErrorHandlerService.shared.saveContext(modelContext, caller: "PhotoHeroCell.saveCaption")
            }
            .presentationDetents([.medium])
        }
        .task {
            if let image = await PhotoThumbnailLoader.load(for: photo, maxPixelSize: 1200) {
                thumbnail = image
                if image.size.height > 0 {
                    imageAspectRatio = image.size.width / image.size.height
                }
            } else {
                loadFailed = true
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var imageLayer: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else if loadFailed {
            Rectangle()
                .fill(Color(.systemGray5))
                .overlay {
                    Image(systemName: photo.cloudURL != nil ? "icloud.and.arrow.down" : "photo")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                }
        } else {
            Rectangle()
                .fill(Color(.systemGray5))
                .overlay { ProgressView() }
        }
    }

    private var recentPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text("Most Recent")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
    }

    private func syncBadge(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(color)
            .cornerRadius(7)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }

    private var syncIndicatorIcon: (name: String, color: Color)? {
        if photo.cloudURL != nil && photo.firestoreId != nil { return nil }
        if photo.cloudURL != nil { return ("exclamationmark.icloud.fill", .yellow) }
        return ("iphone", Color.gray.opacity(0.7))
    }

    @ViewBuilder
    private var bottomScrim: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let caption = photo.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 6) {
                if let game = photo.game {
                    Text("vs \(game.opponent)")
                } else if photo.practice != nil {
                    Text("Practice")
                }
                if (photo.game != nil || photo.practice != nil) && photo.createdAt != nil {
                    Text("·")
                }
                if let date = photo.createdAt {
                    Text(date, style: .date)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.9))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
