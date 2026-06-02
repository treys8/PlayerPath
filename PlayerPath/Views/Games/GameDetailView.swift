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
    @State private var showingScoreEntry = false
    @State private var gameService: GameService? = nil
    /// Hole picked for per-hole scoring; non-nil presents ScoreHoleSheet.
    /// Use a wrapper instead of a bare Int so `.sheet(item:)` redraws when
    /// the user opens different holes back-to-back.
    @State private var scoreHoleTarget: ScoreHoleTarget? = nil

    private var isGolf: Bool { game.season?.sport == .golf }
    // A single golf game is a "Round" — "Tournament" now means the multi-round
    // GolfTournament container (SchemaV27).
    private var unitNoun: String { isGolf ? "Round" : "Game" }
    private var unitNounLower: String { isGolf ? "round" : "game" }

    // Bulk import from Photos — state owned by BulkImportAttach modifier.
    @State private var importTrigger = false

    var videoClips: [VideoClip] {
        (game.videoClips ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var gamePhotos: [Photo] {
        (game.photos ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// Per-hole rows for this game, ascending by hole. Empty when none entered.
    private var holeScores: [HoleScore] {
        (game.holeScores ?? []).sorted { $0.holeNumber < $1.holeNumber }
    }

    /// First unscored hole in 1…holes, or nil once every hole is scored. Drives
    /// the live "Score Hole X" CTA, which is hidden when this is nil so a
    /// finished round can't gain a 19th hole. Returns the first *gap* (not
    /// max+1) so a skipped middle hole is offered before the round is done.
    private var nextHoleNumber: Int? {
        let total = game.holes ?? 18
        let scored = Set(holeScores.map(\.holeNumber))
        return (1...total).first { !scored.contains($0) }
    }

    var body: some View {
        List {
            // Game Info Section
            Section(header: Text(isGolf ? "Round Details" : "Game Details").smallCapsLabel()) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(isGolf ? "Course" : "Opponent")
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
                                // Past-dated games that were never started/ended show
                                // as PAST so the user can tell stats won't count until
                                // they tap Mark Complete.
                                Text(game.isComplete ? "COMPLETED" : "PAST")
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

            // Score Section (golf only)
            if isGolf {
                Section(header: Text("Score").smallCapsLabel()) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Holes")
                                .font(.headingMedium)
                            Spacer()
                            Text("\(game.holes ?? 18)")
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        if let par = game.effectivePar {
                            HStack {
                                Text("Par")
                                    .font(.headingMedium)
                                Spacer()
                                Text("\(par)")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let score = game.effectiveTotalScore {
                            HStack {
                                Text("Total Score")
                                    .font(.headingMedium)
                                Spacer()
                                Text("\(score)")
                                    .monospacedDigit()
                                    .foregroundColor(.primary)
                                if let par = game.effectivePar {
                                    let diff = score - par
                                    Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                                        .font(.labelSmall)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Button(action: { showingScoreEntry = true }) {
                                Label("Enter Score", systemImage: "pencil.line")
                            }
                            .labelStyle(ActionRowLabelStyle())
                        }
                    }
                    .padding(.vertical, 5)
                }

                // Per-hole grid — read-only summary that's also tappable to edit
                // any prior hole. Only renders once at least one hole is scored.
                if !holeScores.isEmpty {
                    Section(header: Text("Holes").smallCapsLabel()) {
                        HoleScoreGrid(
                            holes: holeScores,
                            onTap: { hole in
                                scoreHoleTarget = ScoreHoleTarget(holeNumber: hole.holeNumber)
                            }
                        )
                        .padding(.vertical, 4)
                    }
                }
            }

            // Quick Actions Section — driven by `displayStatus` so the action
            // set always agrees with the badge.
            //   .scheduled:                 Record → Start → Photo → Stats → Edit → Delete
            //   .live:                      Record → End   → Photo → Stats → Edit
            //   .completed && isComplete:   Upload → Photo → Stats → Edit → Restart → Delete
            //   .completed && !isComplete:  Upload → Mark Complete → Photo → Stats → Edit → Delete
            Section(header: Text("Actions").smallCapsLabel()) {
                switch game.displayStatus {
                case .scheduled:
                    Button(action: { showingVideoRecorder = true }) {
                        Label("Record Video", systemImage: "video.badge.plus")
                    }
                    Button(action: { startGame() }) {
                        Label(isGolf ? "Start Round" : "Start Game", systemImage: "play.circle")
                    }
                case .live:
                    // Score Hole is promoted above Record Video for golf live
                    // tournaments — entering a score is the primary action on
                    // each hole, and clip attribution depends on it.
                    if isGolf, let next = nextHoleNumber {
                        Button(action: {
                            scoreHoleTarget = ScoreHoleTarget(holeNumber: next)
                        }) {
                            Label("Score Hole \(next)", systemImage: "flag.checkered")
                        }
                    }
                    Button(action: { showingVideoRecorder = true }) {
                        Label("Record Video", systemImage: "video.badge.plus")
                    }
                    Button(role: .destructive) {
                        Haptics.warning()
                        showingEndGame = true
                    } label: {
                        Label(isGolf ? "End Round" : "End Game", systemImage: "stop.circle")
                    }
                    .labelStyle(DestructiveRowLabelStyle())
                case .completed:
                    Button(action: { importTrigger = true }) {
                        Label("Upload Video", systemImage: "square.and.arrow.down.on.square")
                    }
                    if !game.isComplete {
                        Button(action: { completeGame() }) {
                            Label("Mark Complete", systemImage: "checkmark.circle")
                        }
                    }
                }

                // Content: photo (menu — Take Photo / Choose from Library)
                addPhotoMenu

                // Data entry — manual stats are baseball/softball only. Golf
                // tournaments use the Score section above.
                if !isGolf {
                    Button(action: { showingManualStats = true }) {
                        Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                    }
                } else if game.effectiveTotalScore != nil {
                    Button(action: { showingScoreEntry = true }) {
                        Label("Edit Score", systemImage: "pencil.line")
                    }
                }

                // Metadata
                Button(action: { showingEditGame = true }) {
                    Label(isGolf ? "Edit Tournament" : "Edit Game", systemImage: "pencil")
                }

                if game.isComplete {
                    Button(action: { restartGame() }) {
                        Label(isGolf ? "Restart Round" : "Restart Game", systemImage: "arrow.counterclockwise")
                    }
                }

                // Destructive
                if !game.isLive {
                    Button(role: .destructive) {
                        Haptics.warning()
                        showingDeleteConfirmation = true
                    } label: {
                        Label(isGolf ? "Delete Round" : "Delete Game", systemImage: "trash")
                    }
                    .labelStyle(DestructiveRowLabelStyle())
                }
            }
            .labelStyle(ActionRowLabelStyle())

            // Video Clips Section
            Section(header: Text("Video Clips (\(videoClips.count))").smallCapsLabel()) {
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
            Section(header: Text("Photos (\(gamePhotos.count))").smallCapsLabel()) {
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

            // Game Statistics — hidden for golf (scoring lives in the Score section above)
            if !isGolf, let stats = game.gameStats {
                Section(header: Text("Game Statistics").smallCapsLabel()) {
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
                    // Runs and RBIs omitted — derivable-stats-only (no game context).
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
        .ppDetailBackground()
        .navigationTitle("\(isGolf ? "at" : "vs") \(game.opponent)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { primaryActionMenu }
        .alert(isGolf ? "End Round" : "End Game", isPresented: $showingEndGame) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                Haptics.heavy()
                endGame()
            }
        } message: {
            Text("Are you sure you want to end this \(unitNounLower)? You won't be able to record more videos for it.")
        }
        .alert(isGolf ? "Delete Round" : "Delete Game", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Haptics.heavy()
                deleteGame()
            }
        } message: {
            if game.isComplete, !videoClips.isEmpty || game.gameStats != nil {
                let clipCount = videoClips.count
                let hasStats = !isGolf && game.gameStats != nil
                if clipCount > 0 && hasStats {
                    Text("This \(unitNounLower) has \(clipCount) video clip\(clipCount == 1 ? "" : "s") and recorded statistics. Deleting it will permanently remove all data and recalculate career stats.")
                } else if clipCount > 0 {
                    Text("This \(unitNounLower) has \(clipCount) video clip\(clipCount == 1 ? "" : "s"). Deleting it will permanently remove all data.")
                } else {
                    Text("This \(unitNounLower) has recorded statistics. Deleting it will permanently remove all data and recalculate career stats.")
                }
            } else {
                Text("Are you sure you want to delete this \(unitNounLower)? This action cannot be undone.")
            }
        }
        .sheet(isPresented: $showingScoreEntry) {
            EnterScoreSheet(game: game)
        }
        .sheet(item: $scoreHoleTarget) { target in
            ScoreHoleSheet(game: game, holeNumber: target.holeNumber)
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

    @ToolbarContentBuilder
    private var primaryActionMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                switch game.displayStatus {
                case .scheduled:
                    Button(action: { showingVideoRecorder = true }) {
                        Label("Record Video", systemImage: "video.badge.plus")
                    }
                    Button(action: { startGame() }) {
                        Label(isGolf ? "Start Round" : "Start Game", systemImage: "play.circle")
                    }
                case .live:
                    if isGolf, let next = nextHoleNumber {
                        Button(action: {
                            scoreHoleTarget = ScoreHoleTarget(holeNumber: next)
                        }) {
                            Label("Score Hole \(next)", systemImage: "flag.checkered")
                        }
                    }
                    Button(action: { showingVideoRecorder = true }) {
                        Label("Record Video", systemImage: "video.badge.plus")
                    }
                    Button(action: { Haptics.warning(); showingEndGame = true }) {
                        Label(isGolf ? "End Round" : "End Game", systemImage: "stop.circle")
                    }
                case .completed:
                    Button(action: { importTrigger = true }) {
                        Label("Upload Video", systemImage: "square.and.arrow.down.on.square")
                    }
                    if !game.isComplete {
                        Button(action: { completeGame() }) {
                            Label("Mark Complete", systemImage: "checkmark.circle")
                        }
                    }
                }

                addPhotoMenu

                Divider()

                if !isGolf {
                    Button(action: { showingManualStats = true }) {
                        Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                    }
                } else {
                    Button(action: { showingScoreEntry = true }) {
                        Label(game.effectiveTotalScore == nil ? "Enter Score" : "Edit Score", systemImage: "pencil.line")
                    }
                }

                Button(action: { showingEditGame = true }) {
                    Label(isGolf ? "Edit Tournament" : "Edit Game", systemImage: "pencil")
                }

                if game.isComplete {
                    Divider()
                    Button(action: { restartGame() }) {
                        Label(isGolf ? "Restart Round" : "Restart Game", systemImage: "arrow.counterclockwise")
                    }
                }

                if !game.isLive {
                    if !game.isComplete { Divider() }
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label(isGolf ? "Delete Round" : "Delete Game", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
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
    private func completeGame() {
        Task { await gameService?.complete(game) }
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
