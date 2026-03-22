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
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.title)
                    .foregroundColor(.brandNavy)

                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.name)
                        .font(.headline)

                    Text("\(videoCount) video\(videoCount == 1 ? "" : "s")")
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
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - All Videos Tab View

struct AllVideosTabView: View {
    let folder: SharedFolder
    let videos: [CoachVideoItem]
    var isLoading: Bool = false
    var errorMessage: String? = nil
    let onRefresh: () async -> Void
    var onEditTags: ((CoachVideoItem) -> Void)?

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
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(videos) { video in
                            videoNavigationLink(folder: folder, video: video)
                        }
                    }
                    .padding()
                }
                .refreshable { await onRefresh() }
            }
        }
    }

    @ViewBuilder
    private func videoNavigationLink(folder: SharedFolder, video: CoachVideoItem) -> some View {
        let link = NavigationLink(destination: CoachVideoPlayerView(folder: folder, video: video)) {
            CoachVideoRow(video: video)
        }
        .buttonStyle(.plain)

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

struct CoachVideoRow: View {
    let video: CoachVideoItem

    var body: some View {
        HStack(spacing: 12) {
            RemoteThumbnailView(
                urlString: video.thumbnailURL,
                size: CGSize(width: 120, height: 68),
                duration: video.duration,
                annotationCount: video.annotationCount,
                contextLabel: video.contextLabel,
                isHighlight: video.isHighlight,
                hasNotes: video.notes != nil && !(video.notes?.isEmpty ?? true)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(video.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    Label(video.uploadedByName, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let date = video.createdAt {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
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
            }

            Spacer()
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
    }
}

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
    let onRefresh: () async -> Void

    @State private var cachedGameGroups: [GameGroup] = []

    var body: some View {
        Group {
            if isLoading && videos.isEmpty {
                ProgressView("Loading game videos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, videos.isEmpty {
                EmptyFolderView(
                    icon: "exclamationmark.triangle",
                    title: "Failed to Load",
                    message: error
                )
            } else if videos.isEmpty {
                EmptyFolderView(
                    icon: "figure.baseball",
                    title: "No Game Videos",
                    message: "Game videos will appear here once they're uploaded."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(cachedGameGroups) { group in
                            GameGroupView(folder: folder, gameGroup: group)
                        }
                    }
                    .padding()
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

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 8) {
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
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(gameGroup.videos) { video in
                    NavigationLink(destination: CoachVideoPlayerView(folder: folder, video: video)) {
                        CoachVideoRow(video: video)
                    }
                    .buttonStyle(.plain)
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
    let onRefresh: () async -> Void

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
                            PracticeGroupView(folder: folder, practiceGroup: group)
                        }
                    }
                    .padding()
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

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 8) {
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
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(practiceGroup.videos) { video in
                    NavigationLink(destination: CoachVideoPlayerView(folder: folder, video: video)) {
                        CoachVideoRow(video: video)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
