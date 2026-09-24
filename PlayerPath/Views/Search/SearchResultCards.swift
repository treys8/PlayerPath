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
                .font(.ppCaptionBold)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .foregroundStyle(ppAccent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(ppAccent.opacity(0.12))
        .clipShape(Capsule())
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
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.divider)
                    .frame(width: CGSize.thumbnailSmall.width, height: CGSize.thumbnailSmall.height)
                    .overlay(
                        Image(systemName: placeholderIcon)
                            .foregroundStyle(Theme.textTertiary)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                content
            }

            Spacer()
        }
        .padding()
        .ppCard()
    }
}

struct VideoSearchResultCard: View {
    let video: VideoClip

    var body: some View {
        SearchResultCard(thumbnailPath: video.thumbnailPath, placeholderIcon: "video.fill") {
            HStack {
                Text(video.displayTagName ?? "Untagged")
                    .font(.ppHeadline)
                    .foregroundStyle(video.displayTagName == nil ? Theme.textSecondary : Theme.textPrimary)
                if video.isHighlight {
                    Image(systemName: "star.fill")
                        .font(.ppCaption)
                        .foregroundStyle(Theme.warning)
                }
            }
            if let game = video.game {
                Text(game.opponentLabel)
                    .font(.ppSubheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let createdAt = video.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.ppCaption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

struct GameSearchResultRow: View {
    @Environment(\.ppAccent) private var ppAccent
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(game.opponentLabel)
                    .font(.ppHeadline)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                switch game.displayStatus {
                case .live:
                    Text("LIVE")
                        .font(.custom("Inter18pt-Bold", size: 11, relativeTo: .caption2))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ppAccent)
                        .clipShape(Capsule())
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.chipGreenText)
                case .scheduled:
                    EmptyView()
                }
            }

            if let date = game.date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.ppFootnote)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let stats = game.gameStats {
                Text("\(stats.hits)-for-\(stats.atBats), \(StatisticsService.shared.formatBattingAverage(stats.battingAverage)) AVG")
                    .font(.ppFootnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
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
                .font(.ppHeadline)
                .foregroundStyle(Theme.textPrimary)

            if let date = practice.date {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.ppFootnote)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let note = matchingNote {
                // Show the note that matched, not just a count — this is the
                // "where did I write that" payoff.
                Text(note.content)
                    .font(.ppFootnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            } else {
                let notesCount = practice.notes?.count ?? 0
                if notesCount > 0 {
                    Text("\(notesCount) note\(notesCount == 1 ? "" : "s")")
                        .font(.ppCaption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}

struct PhotoSearchResultCard: View {
    let photo: Photo

    var body: some View {
        SearchResultCard(thumbnailPath: photo.thumbnailPath, placeholderIcon: "photo") {
            if let caption = photo.caption, !caption.isEmpty {
                Text(caption)
                    .font(.ppHeadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let game = photo.game {
                Text(game.opponentLabel)
                    .font(.ppSubheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else if photo.practice != nil {
                Text("Practice")
                    .font(.ppSubheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let createdAt = photo.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.ppCaption)
                    .foregroundStyle(Theme.textTertiary)
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
                Theme.divider
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
