//
//  CoachFolderComponents.swift
//  PlayerPath
//
//  Extracted from CoachFolderDetailView.swift — shared sub-views used by
//  both CoachFolderDetailView (coach side) and AthleteFoldersListView (athlete side).
//

import SwiftUI

// MARK: - Folder Info Header

struct FolderInfoHeader: View {
    let folder: SharedFolder
    let videoCount: Int
    let lastRefreshed: Date?

    var body: some View {
        HStack(spacing: 12) {
            Label("\(videoCount) video\(videoCount == 1 ? "" : "s")", systemImage: "video")
                .font(.caption)
                .foregroundColor(.secondary)

            if let refreshed = lastRefreshed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.brandNavy)
                    Text("Updated \(refreshed.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - All Videos Tab View

struct AllVideosTabView: View {
    let folder: SharedFolder
    let videos: [CoachVideoItem]
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var hasMoreVideos: Bool = false
    var errorMessage: String? = nil
    var unreadVideoIDs: Set<String> = []
    var targetVideoID: String? = nil
    let onRefresh: () async -> Void
    var onLoadMore: (() async -> Void)?
    var onEditTags: ((CoachVideoItem) -> Void)?
    /// When true (games folders), clips are grouped under per-opponent headers
    /// instead of one flat list, so clips from different games don't blur
    /// together. Pagination, deep-link scroll, and sequence review are preserved.
    var groupByGame: Bool = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The row ID currently pulsing with a highlight after deep-link scroll.
    @State private var highlightedVideoID: String?
    /// Remembers which target we've already highlighted so returning from the
    /// video player doesn't re-pulse the card.
    @State private var handledTargetID: String?
    /// Cached game grouping (games folders only), recomputed when `videos`
    /// changes. Cached so the grouped layout and the review sequence share one
    /// stable ordering instead of recomputing the Dictionary on every row render.
    @State private var cachedGameGroups: [GameGroup] = []

    private var videoGridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)]
        } else {
            return [GridItem(.flexible())]
        }
    }

    var body: some View {
        Group {
            if isLoading && videos.isEmpty {
                ProgressView("Loading videos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, videos.isEmpty {
                EmptyFolderView(
                    icon: "exclamationmark.triangle",
                    title: "Failed to Load",
                    message: error
                )
            } else if videos.isEmpty {
                EmptyFolderView(
                    icon: "video.slash",
                    title: "No Videos Yet",
                    message: "Videos will appear here once you or the athlete uploads them."
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        if groupByGame {
                            groupedVideoContent
                        } else {
                            flatVideoContent
                        }
                    }
                    .refreshable { await onRefresh() }
                    .onAppear {
                        if groupByGame { recomputeGameGroups() }
                        scrollToTargetIfNeeded(proxy: proxy)
                    }
                    .onChange(of: videos.map(\.id)) { _, _ in
                        if groupByGame { recomputeGameGroups() }
                        scrollToTargetIfNeeded(proxy: proxy)
                    }
                }
            }
        }
    }

    private var flatVideoContent: some View {
        LazyVGrid(columns: videoGridColumns, spacing: 16) {
            ForEach(videos) { video in
                videoNavigationLink(folder: folder, video: video)
                    .id(video.id)
            }
            loadMoreButton
        }
        .padding(.vertical)
        .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
    }

    private var groupedVideoContent: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(cachedGameGroups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    gameGroupHeader(group)
                    LazyVGrid(columns: videoGridColumns, spacing: 16) {
                        ForEach(group.videos) { video in
                            videoNavigationLink(folder: folder, video: video)
                                .id(video.id)
                        }
                    }
                }
            }
            loadMoreButton
        }
        .padding(.vertical)
        .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
    }

    @ViewBuilder
    private var loadMoreButton: some View {
        if hasMoreVideos {
            Button {
                Task { await onLoadMore?() }
            } label: {
                if isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("Load More Videos")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.brandNavy)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .disabled(isLoadingMore)
        }
    }

    /// Recomputes `cachedGameGroups`: clips grouped by opponent AND game day, so
    /// two games against the same opponent on different dates (or a season's
    /// repeat matchups) stay separate — keying on opponent alone would merge a
    /// May "Eagles" game with a June one. Same-day doubleheaders still merge
    /// (CoachVideoItem carries no game id to split them). Each group is
    /// newest-first; groups are ordered most-recent first.
    private func recomputeGameGroups() {
        let grouped = Dictionary(grouping: videos) { video -> String in
            let opponent = video.gameOpponent ?? "Other"
            let day = video.gameDate ?? video.createdAt
            let dayKey = day.map { Calendar.current.startOfDay(for: $0).timeIntervalSince1970 } ?? 0
            return "\(opponent)|\(dayKey)"
        }
        cachedGameGroups = grouped.map { _, vids in
            GameGroup(
                opponent: vids.first?.gameOpponent ?? "Other",
                date: vids.first?.gameDate ?? vids.compactMap(\.createdAt).max() ?? Date(),
                videos: vids.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            )
        }
        .sorted { $0.date > $1.date }
    }

    /// The clip order a coach actually sees, used to build the review sequence so
    /// Next/Previous and the "n of m" position follow the on-screen order rather
    /// than the raw chronological `videos` array (which differs once grouped).
    private var orderedVideos: [CoachVideoItem] {
        groupByGame ? cachedGameGroups.flatMap(\.videos) : videos
    }

    private func gameGroupHeader(_ group: GameGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.opponent)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(group.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(group.videos.count) video\(group.videos.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func scrollToTargetIfNeeded(proxy: ScrollViewProxy) {
        guard let target = targetVideoID,
              handledTargetID != target,
              videos.contains(where: { $0.id == target })
        else { return }
        handledTargetID = target
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(target, anchor: .center)
            highlightedVideoID = target
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run { highlightedVideoID = nil }
        }
    }

    @ViewBuilder
    private func videoNavigationLink(folder: SharedFolder, video: CoachVideoItem) -> some View {
        // Push a sequence over the on-screen order starting at this clip so the
        // coach can step next/previous without backing out — and so Next follows
        // the cards they see (grouped order when grouped), not raw chronology.
        // Falls back to index 0 if the clip somehow isn't in the list.
        let sequence = orderedVideos
        let startIndex = sequence.firstIndex(where: { $0.id == video.id }) ?? 0
        let link = NavigationLink(
            destination: CoachReviewSequenceView(folder: folder, clips: sequence, startIndex: startIndex)
        ) {
            CoachVideoCard(
                video: video,
                isUnread: unreadVideoIDs.contains(video.id),
                isHighlighted: highlightedVideoID == video.id
            )
        }
        .buttonStyle(PressableCardButtonStyle())

        if let onEditTags {
            link.contextMenu {
                Button {
                    onEditTags(video)
                } label: {
                    Label("Edit Tags", systemImage: "tag")
                }
            }
        } else {
            link
        }
    }
}

// MARK: - Video Row Component

struct CoachVideoCard: View {
    let video: CoachVideoItem
    var isUnread: Bool = false
    var isHighlighted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail — 16:9 aspect ratio, full width
            ZStack {
                RemoteThumbnailView(
                    urlString: video.thumbnailURL,
                    size: CGSize(width: 120, height: 68),
                    cornerRadius: 0,
                    duration: video.duration,
                    annotationCount: video.annotationCount,
                    drawingCount: video.drawingCount,
                    contextLabel: video.contextLabel,
                    isHighlight: video.isHighlight,
                    hasNotes: video.notes != nil && !(video.notes?.isEmpty ?? true),
                    fillsContainer: true,
                    folderID: video.sharedFolderID,
                    videoFileName: video.fileName
                )

                // Gradient overlay for contrast (matches VideoClipCard)
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                }
                // Unread feedback indicator
                if isUnread {
                    VStack {
                        HStack {
                            Text("New")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(Capsule())
                                .padding(8)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // "Viewed" receipt — visible on coach-uploaded clips after the
                // athlete has played them at least once. firestore.rules limits
                // viewedBy writes to the folder owner, so any presence implies
                // the athlete has watched.
                if video.uploadedByType == .coach,
                   let viewedBy = video.viewedBy, !viewedBy.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Label("Viewed", systemImage: "eye.fill")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(8)
                        }
                    }
                }
            }
            .aspectRatio(16/9, contentMode: .fit)

            // Info section
            VStack(alignment: .leading, spacing: 6) {
                Text(video.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(video.uploadedByName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let date = video.createdAt {
                        Text("\u{2022}")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(date, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if !video.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(video.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.brandNavy.opacity(0.1))
                                .foregroundColor(.brandNavy)
                                .cornerRadius(4)
                        }
                        if video.tags.count > 3 {
                            Text("+\(video.tags.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let club = video.club {
                    let clubColor = Club(rawValue: club)?.category.color ?? .brandNavy
                    HStack(spacing: 4) {
                        Text(club)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(clubColor.opacity(0.15))
                            .foregroundColor(clubColor)
                            .cornerRadius(4)
                        if let hole = video.holeNumber {
                            Text("Hole \(hole)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                .stroke(Color.brandNavy.opacity(isHighlighted ? 0.9 : 0), lineWidth: 3)
        )
        .animation(.easeInOut(duration: 0.45), value: isHighlighted)
    }
}

/// Backward-compatible alias
typealias CoachVideoRow = CoachVideoCard

// MARK: - Empty State View

struct EmptyFolderView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Games Tab View

struct GamesTabView: View {
    let folder: SharedFolder
    let videos: [CoachVideoItem]
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var unreadVideoIDs: Set<String> = []
    let onRefresh: () async -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var cachedGameGroups: [GameGroup] = []

    var body: some View {
        Group {
            if isLoading && videos.isEmpty {
                ProgressView("Loading videos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, videos.isEmpty {
                EmptyFolderView(
                    icon: "exclamationmark.triangle",
                    title: "Failed to Load",
                    message: error
                )
            } else if videos.isEmpty {
                EmptyFolderView(
                    icon: "video.slash",
                    title: "No Videos Yet",
                    message: "Videos will appear here once they're uploaded."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(cachedGameGroups) { group in
                            GameGroupView(folder: folder, gameGroup: group, unreadVideoIDs: unreadVideoIDs)
                        }
                    }
                    .padding(.vertical)
                    .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
                }
                .refreshable { await onRefresh() }
            }
        }
        .onAppear { updateGroupedVideos() }
        .onChange(of: videos) { updateGroupedVideos() }
    }

    private func updateGroupedVideos() {
        let grouped = Dictionary(grouping: videos) { video -> String in
            video.gameOpponent ?? "Unknown Game"
        }

        cachedGameGroups = grouped.map { opponent, videos in
            GameGroup(
                opponent: opponent,
                date: videos.first?.createdAt ?? Date(),
                videos: videos.sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
            )
        }.sorted { $0.date > $1.date }
    }
}

struct GameGroup: Identifiable {
    var id: String { "\(opponent)-\(date.timeIntervalSince1970)" }
    let opponent: String
    let date: Date
    let videos: [CoachVideoItem]
}

struct GameGroupView: View {
    let folder: SharedFolder
    let gameGroup: GameGroup
    var unreadVideoIDs: Set<String> = []

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isExpanded = true

    private var videoGridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)]
        } else {
            return [GridItem(.flexible())]
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gameGroup.opponent)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(gameGroup.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Text("\(gameGroup.videos.count) video\(gameGroup.videos.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(.cornerLarge)
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVGrid(columns: videoGridColumns, spacing: 16) {
                    ForEach(gameGroup.videos) { video in
                        NavigationLink(destination: CoachVideoPlayerView(folder: folder, video: video)) {
                            CoachVideoCard(video: video, isUnread: unreadVideoIDs.contains(video.id))
                        }
                        .buttonStyle(PressableCardButtonStyle())
                    }
                }
            }
        }
    }
}

// MARK: - Instruction Tab View

struct InstructionTabView: View {
    let folder: SharedFolder
    let videos: [CoachVideoItem]
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var unreadVideoIDs: Set<String> = []
    let onRefresh: () async -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var cachedPracticeGroups: [PracticeGroup] = []

    var body: some View {
        Group {
            if isLoading && videos.isEmpty {
                ProgressView("Loading instruction videos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, videos.isEmpty {
                EmptyFolderView(
                    icon: "exclamationmark.triangle",
                    title: "Failed to Load",
                    message: error
                )
            } else if videos.isEmpty {
                EmptyFolderView(
                    icon: "figure.run",
                    title: "No Instruction Videos",
                    message: "Instruction videos will appear here once they're uploaded."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(cachedPracticeGroups) { group in
                            PracticeGroupView(folder: folder, practiceGroup: group, unreadVideoIDs: unreadVideoIDs)
                        }
                    }
                    .padding(.vertical)
                    .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
                }
                .refreshable { await onRefresh() }
            }
        }
        .onAppear { updateGroupedVideos() }
        .onChange(of: videos) { updateGroupedVideos() }
    }

    private func updateGroupedVideos() {
        let grouped = Dictionary(grouping: videos) { video -> Date in
            let calendar = Calendar.current
            return calendar.startOfDay(for: video.practiceDate ?? video.createdAt ?? Date())
        }

        cachedPracticeGroups = grouped.map { date, videos in
            PracticeGroup(
                date: date,
                videos: videos.sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
            )
        }.sorted { $0.date > $1.date }
    }
}

struct PracticeGroup: Identifiable {
    var id: TimeInterval { date.timeIntervalSince1970 }
    let date: Date
    let videos: [CoachVideoItem]
}

struct PracticeGroupView: View {
    let folder: SharedFolder
    let practiceGroup: PracticeGroup
    var unreadVideoIDs: Set<String> = []

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isExpanded = true

    private var videoGridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)]
        } else {
            return [GridItem(.flexible())]
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Instruction")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(practiceGroup.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Text("\(practiceGroup.videos.count) video\(practiceGroup.videos.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(.cornerLarge)
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVGrid(columns: videoGridColumns, spacing: 16) {
                    ForEach(practiceGroup.videos) { video in
                        NavigationLink(destination: CoachVideoPlayerView(folder: folder, video: video)) {
                            CoachVideoCard(video: video, isUnread: unreadVideoIDs.contains(video.id))
                        }
                        .buttonStyle(PressableCardButtonStyle())
                    }
                }
            }
        }
    }
}
