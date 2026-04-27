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
    @State private var showingDeleteConfirmation = false
    @State private var showingManualStats = false
    @State private var showingEditGame = false
    @State private var showingPhotoCamera = false
    @State private var showingPhotoLibrary = false
    @State private var gameService: GameService? = nil

    // Bulk import from Photos — state owned by BulkImportAttach modifier.
    @State private var importTrigger = false

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
                            .font(.headingMedium)
                        Spacer()
                        Text(game.opponent)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Date")
                            .font(.headingMedium)
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
                                .font(.headingMedium)
                            Spacer()
                            Text(location)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Status")
                            .font(.headingMedium)
                        Spacer()

                        Group {
                            switch game.displayStatus {
                            case .live:
                                Text("LIVE")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .cornerRadius(4)
                            case .completed:
                                Text("COMPLETED")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray)
                                    .cornerRadius(4)
                            case .scheduled:
                                Text("SCHEDULED")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.brandNavy)
                                    .cornerRadius(4)
                            }
                        }
                        .font(.custom("Inter18pt-Bold", size: 12, relativeTo: .caption))
                    }

                    if let notes = game.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.headingMedium)
                            Text(notes)
                                .foregroundColor(.secondary)
                                .font(.bodyMedium)
                        }
                    }
                }
                .padding(.vertical, 5)
            }

            // Quick Actions Section — state-dependent ordering:
            //   New game:  Record → Start → Add Photo → Stats → Edit → Delete
            //   Live:      Record → End → Add Photo → Stats → Edit
            //   Completed: Upload → Add Photo → Stats → Edit → Restart → Delete
            Section("Actions") {
                if !game.isComplete {
                    // Primary content action: live recording
                    Button(action: { showingVideoRecorder = true }) {
                        Label("Record Video", systemImage: "video.badge.plus")
                    }

                    // Primary state action at #2 — Start for a new game, End mid-game
                    if game.isLive {
                        Button(role: .destructive) {
                            Haptics.warning()
                            showingEndGame = true
                        } label: {
                            Label("End Game", systemImage: "stop.circle")
                        }
                    } else {
                        Button(action: { startGame() }) {
                            Label("Start Game", systemImage: "play.circle")
                        }
                    }
                } else {
                    // Completed: primary content action is importing footage after the fact
                    Button(action: { importTrigger = true }) {
                        Label("Upload Video", systemImage: "square.and.arrow.down.on.square")
                    }
                }

                // Content: photo (menu — Take Photo / Choose from Library)
                addPhotoMenu

                // Data entry
                Button(action: { showingManualStats = true }) {
                    Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                }

                // Metadata
                Button(action: { showingEditGame = true }) {
                    Label("Edit Game", systemImage: "pencil")
                }

                // Restart Game is rarely used — place near the bottom for completed games only.
                if game.isComplete {
                    Button(action: { restartGame() }) {
                        Label("Restart Game", systemImage: "arrow.counterclockwise")
                    }
                }

                // Destructive
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
                        .font(.bodyMedium)
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
                        .font(.bodyMedium)
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
                            .font(.headingMedium)
                    }
                    HStack {
                        Text("Hits")
                        Spacer()
                        Text("\(stats.hits)")
                            .font(.headingMedium)
                    }
                    HStack {
                        Text("Runs")
                        Spacer()
                        Text("\(stats.runs)")
                            .font(.headingMedium)
                    }
                    HStack {
                        Text("RBIs")
                        Spacer()
                        Text("\(stats.rbis)")
                            .font(.headingMedium)
                    }
                    HStack {
                        Text("Strikeouts")
                        Spacer()
                        Text("\(stats.strikeouts)")
                            .font(.headingMedium)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Ground Outs")
                        Spacer()
                        Text("\(stats.groundOuts)")
                            .font(.headingMedium)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Fly Outs")
                        Spacer()
                        Text("\(stats.flyOuts)")
                            .font(.headingMedium)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Walks")
                        Spacer()
                        Text("\(stats.walks)")
                            .font(.headingMedium)
                    }

                    // Calculate and show batting average for this game
                    if stats.atBats > 0 {
                        HStack {
                            Text("Batting Average")
                            Spacer()
                            Text(String(format: "%.3f", Double(stats.hits) / Double(stats.atBats)))
                                .font(.headingMedium)
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
                    // Content group
                    if !game.isComplete {
                        Button(action: { showingVideoRecorder = true }) {
                            Label("Record Video", systemImage: "video.badge.plus")
                        }

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
                        Button(action: { importTrigger = true }) {
                            Label("Upload Video", systemImage: "square.and.arrow.down.on.square")
                        }
                    }

                    addPhotoMenu

                    Divider()

                    // Data + metadata group
                    Button(action: { showingManualStats = true }) {
                        Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                    }

                    Button(action: { showingEditGame = true }) {
                        Label("Edit Game", systemImage: "pencil")
                    }

                    // State-change + destructive group
                    if game.isComplete {
                        Divider()

                        Button(action: { restartGame() }) {
                            Label("Restart Game", systemImage: "arrow.counterclockwise")
                        }
                    }

                    if !game.isLive {
                        if !game.isComplete { Divider() }
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
        .bulkImportAttach(athlete: game.athlete, game: game, trigger: $importTrigger)
        .sheet(isPresented: $showingManualStats) {
            ManualStatisticsEntryView(game: game)
        }
        .sheet(isPresented: $showingEditGame) {
            EditGameSheet(game: game)
        }
        .fullScreenCover(isPresented: $showingPhotoCamera) {
            PhotoCameraView(
                onPhotoCaptured: { image in
                    saveGamePhoto(image)
                    showingPhotoCamera = false
                },
                onCancel: { showingPhotoCamera = false }
            )
        }
        .fullScreenCover(isPresented: $showingPhotoLibrary) {
            ImagePicker(sourceType: .photoLibrary, allowsEditing: false) { image in
                saveGamePhoto(image)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if gameService == nil { gameService = GameService(modelContext: modelContext) }
        }
    }

    private var addPhotoMenu: some View {
        Menu {
            if PhotoCameraAvailability.isCameraAvailable {
                Button(action: { showingPhotoCamera = true }) {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            Button(action: { showingPhotoLibrary = true }) {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Label("Add Photo", systemImage: "camera")
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
                    .font(.headingMedium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let date = photo.createdAt {
                    Text(date, style: .date)
                        .font(.bodySmall)
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
        let path = photo.resolvedFilePath
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let url = URL(fileURLWithPath: path) as CFURL
            guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 150,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
        thumbnail = image
    }
}
