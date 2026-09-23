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
    @State private var showingDeleteConfirm = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        // Sized by the aspectRatio below; no GeometryReader, which is costly
        // per-cell inside a LazyVGrid. The image fills and is top-anchored so
        // faces in portrait shots stay in frame.
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay(alignment: .top) {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                if thumbnail == nil {
                    if loadFailed {
                        Image(systemName: photo.cloudURL != nil ? "icloud.and.arrow.down" : "photo")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                if photo.caption?.isEmpty == false {
                    captionIndicator
                }
            }
            .overlay(alignment: .topTrailing) {
                if let icon = syncIndicatorIcon {
                    syncBadge(icon: icon.name, color: icon.color)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if photo.game == nil && photo.practice == nil {
                    untaggedDot
                }
            }
            .overlay(alignment: .bottomLeading) {
                if photo.isHighlight {
                    highlightBadge
                }
            }
        .aspectRatio(style == .card ? 3.0/4.0 : 1.0, contentMode: .fit)
        .background(style == .card ? Color(.systemGray6) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: style == .card ? 12 : 0, style: .continuous))
        .shadow(color: .black.opacity(style == .card ? 0.08 : 0), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(style == .card ? 0.04 : 0), radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PhotoAccessibility.label(for: photo))
        .accessibilityAddTraits(.isImage)
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
                    photo.isHighlight.toggle()
                    photo.needsSync = true
                    ErrorHandlerService.shared.saveContext(modelContext, caller: "PhotoThumbnailCell.toggleHighlight")
                    Haptics.light()
                } label: {
                    Label(photo.isHighlight ? "Remove Favorite" : "Favorite",
                          systemImage: photo.isHighlight ? "star.slash" : "star")
                }

                Button {
                    showingTagSheet = true
                } label: {
                    Label(photo.athlete?.sport == .golf ? "Tag to Tournament/Practice" : "Tag to Game/Practice", systemImage: "tag")
                }

                Button {
                    captionText = photo.caption ?? ""
                    showingCaptionSheet = true
                } label: {
                    Label(photo.caption != nil ? "Edit Caption" : "Add Caption", systemImage: "text.bubble")
                }

                Divider()

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Photo", systemImage: "trash")
                }
            }
            .onAppear { onContextMenuOpened?() }
        }
        // Confirm here rather than in each host so every grid that embeds this
        // cell (Photos, game + practice pages) gets it. Deletes are permanent.
        .confirmationDialog("Delete this photo?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This can't be undone.")
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
            .fill(ppAccent)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            .padding(8)
            .accessibilityLabel("Untagged — not linked to a game or practice")
    }

    private var highlightBadge: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(5)
            .background(Color.yellow, in: Circle())
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .padding(8)
            .accessibilityLabel("Favorite")
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

// MARK: - Accessibility

/// One spoken description for a photo cell, shared by the grid and hero cells:
/// "Photo, vs Hawks, April 14, 2026, favorite, caption: Walk-off".
enum PhotoAccessibility {
    static func label(for photo: Photo) -> String {
        var parts = ["Photo"]
        if let game = photo.game {
            parts.append(game.opponentLabel)
        } else if photo.practice != nil {
            parts.append("Practice")
        } else {
            parts.append("untagged")
        }
        if let date = photo.createdAt {
            parts.append(date.formatted(date: .long, time: .omitted))
        }
        if photo.isHighlight { parts.append("favorite") }
        if let caption = photo.caption, !caption.isEmpty {
            parts.append("caption: \(caption)")
        }
        return parts.joined(separator: ", ")
    }
}
