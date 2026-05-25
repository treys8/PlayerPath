//
//  PhotoThumbnailCell.swift
//  PlayerPath
//
//  Photo cell. Metadata (caption / game / date) lives in PhotoDetailView.
//  Style.card → 3:4 with chrome (rounded + shadow). Style.dense → square, no chrome.
//

import SwiftUI
import SwiftData
import ImageIO

struct PhotoThumbnailCell: View {
    enum Style {
        case card
        case dense
    }

    @Bindable var photo: Photo
    var style: Style = .card
    let onDelete: () -> Void
    var onContextMenuOpened: (() -> Void)? = nil

    @State private var thumbnail: UIImage?
    @State private var loadFailed = false
    @State private var showingTagSheet = false
    @State private var showingCaptionSheet = false
    @State private var captionText: String = ""
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                            .clipped()
                    } else if loadFailed {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: geo.size.width, height: geo.size.height)
                            .overlay {
                                Image(systemName: photo.cloudURL != nil ? "icloud.and.arrow.down" : "photo")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: geo.size.width, height: geo.size.height)
                            .overlay { ProgressView() }
                    }
                }

                // Overlay badges
                if photo.caption?.isEmpty == false {
                    VStack {
                        HStack {
                            captionIndicator
                            Spacer()
                        }
                        Spacer()
                    }
                }

                if let icon = syncIndicatorIcon {
                    VStack {
                        HStack {
                            Spacer()
                            syncBadge(icon: icon.name, color: icon.color)
                        }
                        Spacer()
                    }
                }

                if photo.game == nil && photo.practice == nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            untaggedDot
                        }
                    }
                }
            }
        }
        .aspectRatio(style == .card ? 3.0/4.0 : 1.0, contentMode: .fit)
        .background(style == .card ? Color(.systemGray6) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: style == .card ? 12 : 0, style: .continuous))
        .shadow(color: .black.opacity(style == .card ? 0.08 : 0), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(style == .card ? 0.04 : 0), radius: 2, x: 0, y: 1)
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
            .onAppear { onContextMenuOpened?() }
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

    // MARK: - Overlay Subviews

    private var captionIndicator: some View {
        Image(systemName: "text.bubble.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(5)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
            .padding(8)
            .accessibilityLabel("Has caption")
    }

    private var untaggedDot: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            .padding(8)
            .accessibilityLabel("Untagged — not linked to a game or practice")
    }

    private func syncBadge(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .padding(8)
    }

    private var syncIndicatorIcon: (name: String, color: Color)? {
        // Hide when fully synced (the common case) to keep the grid clean.
        if photo.cloudURL != nil && photo.firestoreId != nil { return nil }
        if photo.cloudURL != nil { return ("exclamationmark.icloud.fill", .yellow) }
        return ("iphone", Color.gray.opacity(0.7))
    }

    private func loadThumbnail() async {
        if let image = await PhotoThumbnailLoader.load(for: photo) {
            thumbnail = image
        } else {
            loadFailed = true
        }
    }
}
