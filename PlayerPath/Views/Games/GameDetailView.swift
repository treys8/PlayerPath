//
//  GameDetailView.swift
//  PlayerPath
//
//  Detail view for a single game showing stats, clips, and actions.
//

import SwiftUI
import SwiftData
import ImageIO

struct GameDetailView: View {
    let game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingEndGame = false
    @State private var showingVideoRecorder = false
    @State private var showingUploadRecorder = false
    @State private var showingDeleteConfirmation = false
    @State private var showingManualStats = false
    @State private var showingEditGame = false
    @State private var showingPhotoCamera = false
    @State private var gameService: GameService? = nil

    var videoClips: [VideoClip] {
        (game.videoClips ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var gamePhotos: [Photo] {
        (game.photos ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var body: some View {
        List {
            // Game Info Section
            Section("Game Details") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Opponent")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(game.opponent)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Date")
                            .fontWeight(.semibold)
                        Spacer()
                        if let date = game.date {
                            Text(date, format: .dateTime.month().day().hour().minute())
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unknown Date")
                                .foregroundColor(.secondary)
                        }
                    }

                    if let location = game.location, !location.isEmpty {
                        HStack {
                            Text("Location")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(location)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Status")
                            .fontWeight(.semibold)
                        Spacer()

                        Group {
                            if game.isLive {
                                Text("LIVE")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .cornerRadius(4)
                            } else if game.isComplete {
                                Text("COMPLETED")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray)
                                    .cornerRadius(4)
                            } else {
                                Text("SCHEDULED")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.brandNavy)
                                    .cornerRadius(4)
                            }
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                    }

                    if let notes = game.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .fontWeight(.semibold)
                            Text(notes)
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.vertical, 5)
            }

            // Quick Actions Section
            Section("Actions") {
                if !game.isComplete {
                    Button(action: { showingVideoRecorder = true }) {
                        Label("Record Video", systemImage: "video.badge.plus")
                    }

                    if game.isLive {
                        Button(role: .destructive) {
                            Haptics.warning()
                            showingEndGame = true
                        } label: {
                            Label("End Game", systemImage: "stop.circle")
                        }
                    } else {
                        Button {
                            startGame()
                        } label: {
                            Label("Start Game", systemImage: "play.circle")
                        }
                    }
                } else {
                    Button {
                        restartGame()
                    } label: {
                        Label("Restart Game", systemImage: "arrow.counterclockwise")
                    }

                    Button(action: { showingUploadRecorder = true }) {
                        Label("Upload from Camera Roll", systemImage: "photo.badge.plus")
                    }
                }

                // Edit Game Details - available for all games
                Button(action: { showingEditGame = true }) {
                    Label("Edit Game", systemImage: "pencil")
                }

                Button(action: { showingPhotoCamera = true }) {
                    Label("Add Photo", systemImage: "camera")
                }

                // Manual Statistics Entry
                Button(action: { showingManualStats = true }) {
                    Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                }

                if !game.isLive {
                    Button(role: .destructive) {
                        Haptics.warning()
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Game", systemImage: "trash")
                    }
                }
            }

            // Video Clips Section
            Section("Video Clips (\(videoClips.count))") {
                if videoClips.isEmpty {
                    Text("No videos recorded yet")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(videoClips) { clip in
                        VideoClipRow(clip: clip, hasCoachingAccess: authManager.hasCoachingAccess)
                    }
                }
            }

            // Photos Section
            Section("Photos (\(gamePhotos.count))") {
                if gamePhotos.isEmpty {
                    Text("No photos yet")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(gamePhotos) { photo in
                        NavigationLink {
                            PhotoDetailView(photo: photo) {
                                deleteGamePhoto(photo)
                            }
                        } label: {
                            GamePhotoRow(photo: photo)
                        }
                    }
                }
            }

            // Game Statistics
            if let stats = game.gameStats {
                Section("Game Statistics") {
                    HStack {
                        Text("At Bats")
                        Spacer()
                        Text("\(stats.atBats)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Hits")
                        Spacer()
                        Text("\(stats.hits)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Runs")
                        Spacer()
                        Text("\(stats.runs)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("RBIs")
                        Spacer()
                        Text("\(stats.rbis)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Strikeouts")
                        Spacer()
                        Text("\(stats.strikeouts)")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Ground Outs")
                        Spacer()
                        Text("\(stats.groundOuts)")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Fly Outs")
                        Spacer()
                        Text("\(stats.flyOuts)")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Walks")
                        Spacer()
                        Text("\(stats.walks)")
                            .fontWeight(.semibold)
                    }

                    // Calculate and show batting average for this game
                    if stats.atBats > 0 {
                        HStack {
                            Text("Batting Average")
                            Spacer()
                            Text(String(format: "%.3f", Double(stats.hits) / Double(stats.atBats)))
                                .fontWeight(.semibold)
                                .foregroundColor(.brandNavy)
                        }
                    }
                }
            }
        }
        .navigationTitle("vs \(game.opponent)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // Video Actions
                    if !game.isComplete {
                        Button(action: { showingVideoRecorder = true }) {
                            Label("Record Video", systemImage: "video.badge.plus")
                        }
                    }

                    // Game State Actions
                    if !game.isComplete {
                        if game.isLive {
                            Button(action: { Haptics.warning(); showingEndGame = true }) {
                                Label("End Game", systemImage: "stop.circle")
                            }
                        } else {
                            Button(action: { startGame() }) {
                                Label("Start Game", systemImage: "play.circle")
                            }
                        }
                    } else {
                        Button(action: { restartGame() }) {
                            Label("Restart Game", systemImage: "arrow.counterclockwise")
                        }

                        Button(action: { showingUploadRecorder = true }) {
                            Label("Upload from Camera Roll", systemImage: "photo.badge.plus")
                        }
                    }

                    Button(action: { showingPhotoCamera = true }) {
                        Label("Add Photo", systemImage: "camera")
                    }

                    Divider()

                    // Edit Game Details
                    Button(action: { showingEditGame = true }) {
                        Label("Edit Game", systemImage: "pencil")
                    }

                    // Statistics Action
                    Button(action: { showingManualStats = true }) {
                        Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                    }

                    Divider()

                    // Destructive Actions
                    if !game.isLive {
                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                            Label("Delete Game", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        }
        .alert("End Game", isPresented: $showingEndGame) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                Haptics.heavy()
                endGame()
            }
        } message: {
            Text("Are you sure you want to end this game? You won't be able to record more videos for it.")
        }
        .alert("Delete Game", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Haptics.heavy()
                deleteGame()
            }
        } message: {
            if game.isComplete, !videoClips.isEmpty || game.gameStats != nil {
                let clipCount = videoClips.count
                let hasStats = game.gameStats != nil
                if clipCount > 0 && hasStats {
                    Text("This game has \(clipCount) video clip\(clipCount == 1 ? "" : "s") and recorded statistics. Deleting it will permanently remove all data and recalculate career stats.")
                } else if clipCount > 0 {
                    Text("This game has \(clipCount) video clip\(clipCount == 1 ? "" : "s"). Deleting it will permanently remove all data.")
                } else {
                    Text("This game has recorded statistics. Deleting it will permanently remove all data and recalculate career stats.")
                }
            } else {
                Text("Are you sure you want to delete this game? This action cannot be undone.")
            }
        }
        .fullScreenCover(isPresented: $showingVideoRecorder) {
            DirectCameraRecorderView(athlete: game.athlete, game: game)
        }
        .fullScreenCover(isPresented: $showingUploadRecorder) {
            VideoRecorderView_Refactored(athlete: game.athlete, game: game)
        }
        .sheet(isPresented: $showingManualStats) {
            ManualStatisticsEntryView(game: game)
        }
        .sheet(isPresented: $showingEditGame) {
            EditGameSheet(game: game)
        }
        .fullScreenCover(isPresented: $showingPhotoCamera) {
            ImagePicker(sourceType: .camera, allowsEditing: false) { image in
                saveGamePhoto(image)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if gameService == nil { gameService = GameService(modelContext: modelContext) }
        }
    }

    @MainActor
    private func startGame() {
        Task { await gameService?.start(game) }
    }

    @MainActor
    private func endGame() {
        Task { await gameService?.end(game) }
    }

    @MainActor
    private func restartGame() {
        Task { await gameService?.restart(game) }
    }

    @MainActor
    private func deleteGame() {
        Task {
            await gameService?.deleteGameDeep(game)
            dismiss()
        }
    }

    private func saveGamePhoto(_ image: UIImage) {
        guard let athlete = game.athlete else { return }
        Task {
            do {
                _ = try await PhotoPersistenceService().savePhoto(
                    image: image,
                    context: modelContext,
                    athlete: athlete,
                    game: game
                )
                Haptics.success()
            } catch {
                ErrorHandlerService.shared.handle(error, context: "GameDetail.savePhoto", showAlert: false)
            }
        }
    }

    private func deleteGamePhoto(_ photo: Photo) {
        PhotoPersistenceService().deletePhoto(photo, context: modelContext)
        Haptics.light()
    }
}

// MARK: - Game Photo Row

private struct GamePhotoRow: View {
    let photo: Photo

    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(photo.caption ?? "Photo")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let date = photo.createdAt {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        if let thumbPath = photo.resolvedThumbnailPath {
            if let image = try? await ThumbnailCache.shared.loadThumbnail(at: thumbPath, targetSize: .thumbnailSmall) {
                thumbnail = image
                return
            }
        }
        let url = URL(fileURLWithPath: photo.resolvedFilePath) as CFURL
        if let source = CGImageSourceCreateWithURL(url, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 150,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                thumbnail = UIImage(cgImage: cgImage)
            }
        }
    }
}
