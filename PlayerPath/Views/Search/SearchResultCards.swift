//
//  SearchResultCards.swift
//  PlayerPath
//
//  Result cards, rows and filter chips for AdvancedSearchView.
//

import SwiftUI
import SwiftData

// MARK: - Supporting Views

struct FilterChip: View {
    @Environment(\.ppAccent) private var ppAccent
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.labelMedium)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .foregroundColor(ppAccent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(ppAccent.opacity(0.1))
        .cornerRadius(16)
    }
}

/// Shared card layout for search results with a thumbnail and detail content.
struct SearchResultCard<Content: View>: View {
    let thumbnailPath: String?
    let placeholderIcon: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnailPath {
                AsyncThumbnailView(path: thumbnailPath, size: .thumbnailSmall)
                    .frame(width: CGSize.thumbnailSmall.width, height: CGSize.thumbnailSmall.height)
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: CGSize.thumbnailSmall.width, height: CGSize.thumbnailSmall.height)
                    .cornerRadius(8)
                    .overlay(
                        Image(systemName: placeholderIcon)
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                content
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

struct VideoSearchResultCard: View {
    let video: VideoClip

    var body: some View {
        SearchResultCard(thumbnailPath: video.thumbnailPath, placeholderIcon: "video.fill") {
            HStack {
                Text(video.displayTagName ?? "Untagged")
                    .font(.headingMedium)
                    .foregroundColor(video.displayTagName == nil ? .secondary : .primary)
                if video.isHighlight {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
            }
            if let game = video.game {
                Text(game.opponentLabel)
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
            if let createdAt = video.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct GameSearchResultRow: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(game.opponentLabel)
                    .font(.headingLarge)

                Spacer()

                switch game.displayStatus {
                case .live:
                    Text("LIVE")
                        .font(.custom("Inter18pt-Bold", size: 11, relativeTo: .caption2))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .cornerRadius(4)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .scheduled:
                    EmptyView()
                }
            }

            if let date = game.date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }

            if let stats = game.gameStats {
                Text("\(stats.hits)-for-\(stats.atBats), \(StatisticsService.shared.formatBattingAverage(stats.battingAverage)) AVG")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PracticeSearchResultRow: View {
    let practice: Practice
    /// When the result was surfaced by a note-text match, the active query — used
    /// to show the matching note snippet so the user sees *why* this row matched.
    var searchText: String = ""

    /// The first note whose content matches the active query, if any.
    private var matchingNote: PracticeNote? {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        return (practice.notes ?? []).first { $0.content.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Practice")
                .font(.headingLarge)

            if let date = practice.date {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }

            if let note = matchingNote {
                // Show the note that matched, not just a count — this is the
                // "where did I write that" payoff.
                Text(note.content)
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            } else {
                let notesCount = practice.notes?.count ?? 0
                if notesCount > 0 {
                    Text("\(notesCount) note\(notesCount == 1 ? "" : "s")")
                        .font(.labelSmall)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct PhotoSearchResultCard: View {
    let photo: Photo

    var body: some View {
        SearchResultCard(thumbnailPath: photo.thumbnailPath, placeholderIcon: "photo") {
            if let caption = photo.caption, !caption.isEmpty {
                Text(caption)
                    .font(.headingMedium)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let game = photo.game {
                Text(game.opponentLabel)
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            } else if photo.practice != nil {
                Text("Practice")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
            if let createdAt = photo.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct AsyncThumbnailView: View {
    let path: String
    let size: CGSize

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.3)
                    .overlay(
                        ProgressView()
                    )
            }
        }
        .task {
            do {
                image = try await ThumbnailCache.shared.loadThumbnail(at: path, targetSize: size)
            } catch {
                // Failed to load thumbnail
            }
        }
    }
}
