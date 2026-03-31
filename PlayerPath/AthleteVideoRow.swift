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
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if isUnread {
                        Text("New")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 4) {
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

                if let count = video.annotationCount, count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bubble.left.fill")
                            .font(.caption2)
                        Text("\(count)")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Athlete Video List

struct AthleteVideoListView: View {
    let folder: SharedFolder
    let videos: [CoachVideoItem]
    var unreadVideoIDs: Set<String> = []
    let onRefresh: () async -> Void

    var body: some View {
        if videos.isEmpty {
            EmptyFolderView(
                icon: "video.slash",
                title: "No Videos Yet",
                message: "Videos will appear here once uploaded."
            )
        } else {
            List {
                ForEach(videos) { video in
                    NavigationLink(destination: CoachVideoPlayerView(folder: folder, video: video)) {
                        AthleteVideoRow(video: video, isUnread: unreadVideoIDs.contains(video.id))
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await onRefresh() }
        }
    }
}
