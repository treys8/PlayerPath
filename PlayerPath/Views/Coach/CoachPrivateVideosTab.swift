//
//  CoachPrivateVideosTab.swift
//  PlayerPath
//
//  "My Recordings" tab in CoachFolderDetailView.
//  Coaches record instruction videos here, review them, then
//  share selected clips to the athlete's folder.
//

import SwiftUI

struct CoachPrivateVideosTab: View {
    let folder: SharedFolder
    let canUpload: Bool

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var viewModel = CoachPrivateVideosViewModel()
    @State private var showingCamera = false
    @State private var showingDeleteConfirmation = false
    @State private var videoToDelete: FirestoreVideoMetadata?
    @State private var videoToMove: FirestoreVideoMetadata?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.videos.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading recordings...")
                    Spacer()
                }
            } else if viewModel.videos.isEmpty {
                emptyState
            } else {
                videosList
            }
        }
        .task {
            guard let coachID = authManager.userID,
                  let folderID = folder.id else { return }
            await viewModel.setup(coachID: coachID, sharedFolderID: folderID)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            ModernCameraView(
                onVideoRecorded: { url in
                    showingCamera = false
                    Task { await viewModel.uploadRecording(videoURL: url) }
                },
                onCancel: {
                    showingCamera = false
                }
            )
        }
        .alert("Delete Recording", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let video = videoToDelete {
                    Task { await viewModel.deleteVideo(video) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recording will be permanently deleted. It has not been shared with the athlete.")
        }
        .sheet(item: $videoToMove) { video in
            if let folderID = folder.id {
                let item = CoachRecordingItem(
                    metadata: video,
                    athleteName: folder.ownerAthleteName ?? "Athlete",
                    folderName: folder.name,
                    sharedFolderID: folderID
                )
                MoveAndTagSheet(item: item) { notes, tags, drillType in
                    Task { await viewModel.publishVideo(video, notes: notes, tags: tags, drillType: drillType) }
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "video.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Recordings Yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Record instruction videos here. When you're ready, share them with the athlete along with your notes.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if canUpload {
                Button {
                    showingCamera = true
                } label: {
                    Label("Record Video", systemImage: "video.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Videos List

    private var videosList: some View {
        VStack(spacing: 0) {
            if canUpload {
                Button {
                    showingCamera = true
                } label: {
                    HStack {
                        Image(systemName: "video.fill.badge.plus")
                        Text("Record New Video")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(10)
                }
                .padding()
            }

            List {
                ForEach(viewModel.videos) { video in
                    NavigationLink(destination: CoachVideoPlayerView(
                        folder: folder,
                        video: CoachVideoItem(from: video)
                    )) {
                        PrivateVideoRow(
                            video: video,
                            onMove: {
                                videoToMove = video
                            },
                            onDelete: {
                                videoToDelete = video
                                showingDeleteConfirmation = true
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.loadVideos()
            }

            if viewModel.isPublishing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Sharing with athlete...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
    }
}

// MARK: - Private Video Row

struct PrivateVideoRow: View {
    let video: FirestoreVideoMetadata
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                if let urlString = video.thumbnail?.standardURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            thumbnailPlaceholder
                        }
                    }
                } else {
                    thumbnailPlaceholder
                }
            }
            .frame(width: 80, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let createdAt = video.createdAt {
                    Text(createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    if let fileSize = video.fileSize, fileSize > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let duration = video.duration, duration > 0 {
                        Text(duration.formattedTimestamp)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                onMove()
            } label: {
                Label("Share with Athlete", systemImage: "arrow.right.circle")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                onMove()
            } label: {
                Label("Share", systemImage: "arrow.right.circle")
            }
            .tint(.green)
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color(.systemGray5)
            Image(systemName: "video.fill")
                .foregroundColor(.gray)
        }
    }

    private var displayName: String {
        if let notes = video.notes, !notes.isEmpty {
            return notes
        }
        return video.fileName
            .replacingOccurrences(of: "instruction_", with: "Instruction ")
            .replacingOccurrences(of: "practice_", with: "Instruction ")
            .replacingOccurrences(of: ".mov", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }
}
