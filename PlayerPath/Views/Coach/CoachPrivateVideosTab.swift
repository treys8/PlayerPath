//
//  CoachPrivateVideosTab.swift
//  PlayerPath
//
//  "My Recordings" tab in CoachFolderDetailView.
//  Coaches record practice videos here, review them, then move
//  selected clips to the shared folder.
//

import SwiftUI
import Combine
import FirebaseAuth

struct CoachPrivateVideosTab: View {
    let folder: SharedFolder
    let canUpload: Bool

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var viewModel = CoachPrivateVideosViewModel()
    @State private var showingCamera = false
    @State private var showingDeleteConfirmation = false
    @State private var videoToDelete: CoachPrivateVideo?
    @State private var videoToMove: CoachPrivateVideo?
    @State private var showingMoveAndTag = false

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
            await viewModel.setup(
                coachID: coachID,
                athleteID: folder.ownerAthleteID,
                sharedFolderID: folderID
            )
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
        .sheet(isPresented: $showingMoveAndTag) {
            if let video = videoToMove, let folderID = folder.id {
                let item = CoachRecordingItem(
                    video: video,
                    athleteName: folder.ownerAthleteName ?? "Athlete",
                    folderName: folder.name,
                    sharedFolderID: folderID,
                    privateFolderID: viewModel.privateFolderID ?? ""
                )
                MoveAndTagSheet(item: item) { tags, drillType in
                    Task { await viewModel.moveToSharedFolder(video, tags: tags, drillType: drillType) }
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

            Text("Record practice videos here. When you're ready, move them to the shared folder for the athlete to see.")
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
            // Record button at top
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
                        video: CoachVideoItem(from: video, sharedFolderID: folder.id ?? "")
                    )) {
                        PrivateVideoRow(
                            video: video,
                            isUploading: viewModel.uploadingVideoID == video.id,
                            onMove: {
                                videoToMove = video
                                showingMoveAndTag = true
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

            if viewModel.isMoving {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Moving to shared folder...")
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
    let video: CoachPrivateVideo
    let isUploading: Bool
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                if let urlString = video.thumbnailURL, let url = URL(string: urlString) {
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
                    if let duration = video.duration {
                        Text(formatDuration(duration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if isUploading {
                ProgressView()
            } else {
                // Visual hint that actions are available
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                onMove()
            } label: {
                Label("Move to Shared Folder", systemImage: "arrow.right.circle")
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
        // Show a readable name instead of the raw filename
        if let notes = video.notes, !notes.isEmpty {
            return notes
        }
        return video.fileName
            .replacingOccurrences(of: "practice_", with: "Practice ")
            .replacingOccurrences(of: ".mov", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - CoachVideoItem from Private Video

extension CoachVideoItem {
    init(from privateVideo: CoachPrivateVideo, sharedFolderID: String) {
        self.id = privateVideo.id ?? UUID().uuidString
        self.fileName = privateVideo.fileName
        self.firebaseStorageURL = privateVideo.firebaseStorageURL
        self.thumbnailURL = privateVideo.thumbnailURL
        self.uploadedBy = privateVideo.uploadedBy
        self.uploadedByName = privateVideo.uploadedByName
        self.sharedFolderID = sharedFolderID
        self.createdAt = privateVideo.createdAt
        self.fileSize = privateVideo.fileSize
        self.duration = privateVideo.duration
        self.isHighlight = false
        self.videoType = "practice"
        self.gameOpponent = nil
        self.gameDate = nil
        self.practiceDate = nil
        self.notes = privateVideo.notes
        self.annotationCount = nil
        self.tags = []
        self.drillType = nil
        self.isPrivatePreview = true
    }
}

// MARK: - View Model

@MainActor
class CoachPrivateVideosViewModel: ObservableObject {
    @Published var videos: [CoachPrivateVideo] = []
    @Published var isLoading = false
    @Published var isUploading = false
    @Published var isMoving = false
    @Published var errorMessage: String?
    @Published var uploadingVideoID: String?

    private(set) var privateFolder: CoachPrivateFolder?
    var privateFolderID: String? { privateFolder?.id }
    private var coachID: String?
    private var coachName: String?
    private let firestore = FirestoreManager.shared

    func setup(coachID: String, athleteID: String, sharedFolderID: String) async {
        self.coachID = coachID
        self.coachName = Auth.auth().currentUser?.displayName
            ?? Auth.auth().currentUser?.email
            ?? "Coach"

        do {
            privateFolder = try await firestore.getOrCreatePrivateFolder(
                coachID: coachID,
                athleteID: athleteID,
                sharedFolderID: sharedFolderID
            )
            await loadVideos()
        } catch {
            errorMessage = "Failed to load recordings: \(error.localizedDescription)"
        }
    }

    func loadVideos() async {
        guard let folderID = privateFolder?.id else { return }
        isLoading = true
        do {
            videos = try await firestore.fetchPrivateVideos(privateFolderID: folderID)
        } catch {
            errorMessage = "Failed to load recordings: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func uploadRecording(videoURL: URL) async {
        guard let folderID = privateFolder?.id,
              let sharedFolderID = privateFolder?.sharedFolderID,
              let coachID = coachID,
              let coachName = coachName else { return }

        isUploading = true

        do {
            let dateStr = Date().formatted(.iso8601.year().month().day())
            let fileName = "practice_\(dateStr)_\(UUID().uuidString.prefix(8)).mov"

            // Get file size
            let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            // Upload to Firebase Storage under shared_folders path
            // (same path as shared videos — only Firestore metadata is "private")
            let storageURL = try await VideoCloudManager.shared.uploadVideo(
                localURL: videoURL,
                fileName: fileName,
                folderID: sharedFolderID,
                progressHandler: { _ in }
            )

            // Process video: extract duration + generate/upload thumbnail
            let processed = await CoachVideoProcessingService.shared.process(
                videoURL: videoURL,
                fileName: fileName,
                folderID: sharedFolderID
            )

            // Create metadata in Firestore
            _ = try await firestore.createPrivateVideo(
                privateFolderID: folderID,
                fileName: fileName,
                storageURL: storageURL,
                uploadedBy: coachID,
                uploadedByName: coachName,
                fileSize: fileSize,
                duration: processed.duration,
                thumbnailURL: processed.thumbnailURL,
                notes: nil
            )

            Haptics.success()
            await loadVideos()
        } catch {
            errorMessage = "Failed to save recording: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachPrivateVideosViewModel.uploadRecording", showAlert: false)
        }

        isUploading = false
    }

    func moveToSharedFolder(_ video: CoachPrivateVideo, tags: [String] = [], drillType: String? = nil) async {
        guard let videoID = video.id,
              let folderID = privateFolder?.id,
              let sharedFolderID = privateFolder?.sharedFolderID,
              let coachID = coachID,
              let coachName = coachName else {
            errorMessage = "Unable to share video. Please try again."
            return
        }

        isMoving = true
        uploadingVideoID = videoID

        do {
            try await firestore.moveVideoToSharedFolder(
                privateVideoID: videoID,
                privateFolderID: folderID,
                sharedFolderID: sharedFolderID,
                coachID: coachID,
                coachName: coachName,
                tags: tags,
                drillType: drillType
            )
            Haptics.success()
            await loadVideos()
        } catch {
            errorMessage = "Failed to move video: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachPrivateVideosViewModel.moveToSharedFolder", showAlert: false)
        }

        isMoving = false
        uploadingVideoID = nil
    }

    func deleteVideo(_ video: CoachPrivateVideo) async {
        guard let videoID = video.id,
              let folderID = privateFolder?.id,
              let sharedFolderID = privateFolder?.sharedFolderID else { return }

        do {
            try await firestore.deletePrivateVideo(
                videoID: videoID,
                privateFolderID: folderID,
                sharedFolderID: sharedFolderID,
                fileName: video.fileName
            )
            videos.removeAll { $0.id == videoID }
            Haptics.success()
        } catch {
            errorMessage = "Failed to delete recording: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachPrivateVideosViewModel.deleteVideo", showAlert: false)
        }
    }
}
