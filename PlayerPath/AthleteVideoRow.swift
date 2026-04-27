//
//  AthleteVideoRow.swift
//  PlayerPath
//
//  Compact video row for athlete-side shared folders.
//

import SwiftUI

// MARK: - Compact Video Row

struct AthleteVideoRow: View {
    let video: CoachVideoItem
    var isUnread: Bool = false
    var isHighlighted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            RemoteThumbnailView.medium(
                urlString: video.thumbnailURL,
                folderID: video.sharedFolderID,
                videoFileName: video.fileName
            )
            .frame(width: 80, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(video.displayTitle)
                        .font(.headingMedium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if isUnread {
                        Text("New")
                            .font(.custom("Inter18pt-Bold", size: 11, relativeTo: .caption2))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 4) {
                    Text(video.uploadedByName)
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let date = video.createdAt {
                        Text("\u{2022}")
                            .font(.labelSmall)
                            .foregroundColor(.secondary)
                        Text(date, style: .date)
                            .font(.labelSmall)
                            .foregroundColor(.secondary)
                    }
                }

                // Annotation counts. When drawingCount is known (modern videos),
                // split into pencil + bubble; otherwise legacy lumped bubble.
                AnnotationBadgeCluster(
                    annotationCount: video.annotationCount ?? 0,
                    drawingCount: video.drawingCount,
                    style: .compact
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.brandNavy.opacity(isHighlighted ? 0.14 : 0))
        )
        .animation(.easeInOut(duration: 0.45), value: isHighlighted)
    }
}

// MARK: - Athlete Video List

struct AthleteVideoListView: View {
    let folder: SharedFolder
    let videos: [CoachVideoItem]
    var unreadVideoIDs: Set<String> = []
    var targetVideoID: String? = nil
    let onRefresh: () async -> Void

    /// The row ID currently pulsing with a highlight after deep-link scroll.
    /// Cleared after a short delay so the highlight fades back to normal.
    @State private var highlightedVideoID: String?
    /// Remembers which target we've already highlighted so returning from the
    /// video player doesn't re-pulse the row.
    @State private var handledTargetID: String?

    var body: some View {
        if videos.isEmpty {
            EmptyFolderView(
                icon: "video.slash",
                title: "No Videos Yet",
                message: "Videos will appear here once uploaded."
            )
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(videos) { video in
                        NavigationLink(destination: CoachVideoPlayerView(folder: folder, video: video)) {
                            AthleteVideoRow(
                                video: video,
                                isUnread: unreadVideoIDs.contains(video.id),
                                isHighlighted: highlightedVideoID == video.id
                            )
                        }
                        .id(video.id)
                    }
                }
                .listStyle(.plain)
                .refreshable { await onRefresh() }
                .onAppear { scrollToTargetIfNeeded(proxy: proxy) }
                .onChange(of: videos.map(\.id)) { _, _ in
                    // Videos arrive async — if the target wasn't in the list on first appear,
                    // scroll once it shows up.
                    scrollToTargetIfNeeded(proxy: proxy)
                }
            }
        }
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
        // Fade the highlight out after a beat so the row settles back to normal.
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run { highlightedVideoID = nil }
        }
    }
}
