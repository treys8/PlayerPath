//
//  CoachVideoPlayerViewModel.swift
//  PlayerPath
//
//  ViewModel for CoachVideoPlayerView — handles video loading,
//  annotation CRUD, playback control, and comment mirroring.
//

import SwiftUI
import AVKit
import CoreMedia
import Photos
import FirebaseAuth
import FirebaseFirestore
import PencilKit

@MainActor
@Observable
class CoachVideoPlayerViewModel {
    let video: CoachVideoItem
    let folder: SharedFolder

    var player: AVPlayer?
    var isLoading = false
    var isPlayerReady = false
    var annotations: [VideoAnnotation] = []
    var isLoadingAnnotations = false
    var errorMessage: String?
    var playbackRate: Double = 1.0
    var videoDuration: Double?
    var shouldResumeOnActive = false

    // Local override for the coach note so the player UI re-renders after edits
    // without refetching the parent CoachVideoItem.
    var coachNoteText: String?
    var coachNoteAuthorName: String?
    var coachNoteUpdatedAt: Date?

    // Local override for the per-coach reviewed timestamp. Non-nil = the
    // current coach has reviewed this clip in *this view session*; falls back
    // to `video.reviewedBy[coachID]` for the persisted state. Updated locally
    // after a save so the toolbar button hides immediately without a refetch.
    var reviewedAt: Date?

    // Download & save state
    var isDownloading = false
    var downloadProgress: Double = 0
    var isSaving = false
    var didSaveSuccessfully = false
    var saveError: String?

    // Filmstrip scrubber state
    var filmstripThumbnails: [FilmstripThumbnail] = []
    var isGeneratingFilmstrip = false
    var observedPlaybackTime: Double = 0

    // Telestration state
    struct ActiveDrawingOverlay: Equatable {
        let data: Data
        let canvasSize: CGSize?
    }
    var activeDrawingOverlay: ActiveDrawingOverlay?
    var videoNaturalSize: CGSize?

    private var durationTask: Task<Void, Never>?
    private var filmstripTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var filmstripTimeObserver: Any?
    private var annotationsListener: ListenerRegistration?

    var currentPlaybackTime: Double {
        player?.currentTime().seconds ?? 0.0
    }

    init(video: CoachVideoItem, folder: SharedFolder) {
        self.video = video
        self.folder = folder
        // Seed coach-note state from metadata, with a read-side fallback for
        // legacy instruction clips whose note still lives in the `notes` field.
        if let note = video.coachNote, !note.isEmpty {
            self.coachNoteText = note
            self.coachNoteAuthorName = video.coachNoteAuthorName ?? video.uploadedByName
            self.coachNoteUpdatedAt = video.coachNoteUpdatedAt ?? video.createdAt
        } else if video.uploadedByType == .coach,
                  let legacy = video.notes, !legacy.isEmpty {
            self.coachNoteText = legacy
            self.coachNoteAuthorName = video.uploadedByName
            self.coachNoteUpdatedAt = video.createdAt
        }
    }

    deinit {
        // @MainActor class instances owned by SwiftUI views are deallocated
        // on the main thread, so assumeIsolated is safe here.
        MainActor.assumeIsolated {
            durationTask?.cancel()
            filmstripTask?.cancel()
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
            }
            if let observer = filmstripTimeObserver {
                player?.removeTimeObserver(observer)
            }
            statusObservation?.invalidate()
            annotationsListener?.remove()
            player?.pause()
        }
    }

    // MARK: - Video Loading

    func loadVideo() async {
        // Clean up previous player resources before creating new ones
        stopTimeObserver()
        statusObservation?.invalidate()
        statusObservation = nil

        isLoading = true
        isPlayerReady = false

        let folderID = folder.id ?? ""
        let playbackURL: URL

        if let cached = CoachVideoLoader.cachedURL(folderID: folderID, fileName: video.fileName) {
            playbackURL = cached
        } else {
            isDownloading = true
            do {
                playbackURL = try await CoachVideoLoader.fetchAndCache(
                    folderID: folderID,
                    fileName: video.fileName
                )
            } catch {
                isDownloading = false
                ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.loadVideo", showAlert: false)
                errorMessage = "Unable to load video. Please check your connection and try again."
                isLoading = false
                return
            }
            isDownloading = false
        }

        let newPlayer = AVPlayer(url: playbackURL)
        player = newPlayer

        statusObservation = newPlayer.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isPlayerReady = true
                    self.isLoading = false
                case .failed:
                    self.isLoading = false
                    self.errorMessage = item.error?.localizedDescription ?? "Failed to load video"
                default:
                    break
                }
            }
        }

    }

    // MARK: - Annotations

    func loadAnnotations() async {
        isLoadingAnnotations = true

        let videoID = video.id
        guard !videoID.isEmpty else {
            isLoadingAnnotations = false
            return
        }

        // Seed with a one-shot fetch for fast first paint.
        do {
            annotations = try await FirestoreManager.shared.fetchAnnotations(forVideo: videoID)
                .sorted { $0.timestamp < $1.timestamp }
        } catch {
            // Permission errors are expected for private videos (not yet in shared folder)
            // — annotations don't exist until the video is shared. Don't show error UI.
            let nsError = error as NSError
            if nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7 {
                annotations = []
            } else {
                errorMessage = "Failed to load feedback: \(error.localizedDescription)"
            }
        }

        isLoadingAnnotations = false

        // Attach a live listener so coach feedback added elsewhere (another
        // device, the athlete's player) shows up without a manual refresh.
        annotationsListener?.remove()
        annotationsListener = FirestoreManager.shared.listenToAnnotations(forVideo: videoID) { [weak self] updated in
            guard let self else { return }
            self.annotations = updated.sorted { $0.timestamp < $1.timestamp }
        }
    }

    func addAnnotation(
        text: String,
        timestamp: Double,
        userID: String,
        userName: String,
        isCoachComment: Bool,
        category: String? = nil
    ) async {
        do {
            let videoID = video.id
            guard !videoID.isEmpty else { return }

            let annotation = try await FirestoreManager.shared.createAnnotation(
                videoID: videoID,
                text: text,
                timestamp: timestamp,
                userID: userID,
                userName: userName,
                isCoachComment: isCoachComment,
                category: category
            )

            // The live snapshot listener drives `annotations` from Firestore —
            // no optimistic local append needed (avoids a brief flash when the
            // snapshot overwrites an append mid-flight).

            // Mirror coach feedback to the unified comment thread and record
            // the resulting comment ID on the annotation so delete can pair
            // them precisely instead of matching on text.
            if isCoachComment, let annotationID = annotation.id {
                do {
                    let mirrorID = try await ClipCommentService.shared.postComment(
                        clipId: videoID,
                        text: text,
                        authorId: userID,
                        authorName: userName,
                        authorRole: "coach",
                        category: category
                    )
                    if let mirrorID {
                        await FirestoreManager.shared.setAnnotationMirrorCommentID(
                            videoID: videoID,
                            annotationID: annotationID,
                            mirrorCommentID: mirrorID
                        )
                    }
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.mirrorComment", showAlert: false)
                }
            }

            Haptics.success()

            // Notify the folder owner that a coach left feedback
            if isCoachComment {
                let athleteID = folder.ownerAthleteID
                await ActivityNotificationService.shared.postCoachCommentNotification(
                    videoFileName: video.fileName,
                    folderID: folder.id ?? "",
                    videoID: videoID,
                    coachID: userID,
                    coachName: userName,
                    athleteID: athleteID,
                    notePreview: text
                )
            }

        } catch {
            errorMessage = "Failed to add feedback: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayerViewModel.addAnnotation", showAlert: false)
        }
    }

    /// Persists a coach-authored plain note (or clears it when `text` is nil/empty)
    /// and updates local state so the player card re-renders without a refetch.
    /// Throws on failure so callers can surface the error inline.
    func updateCoachNote(text: String?, authorID: String, authorName: String) async throws {
        let videoID = video.id
        guard !videoID.isEmpty else { return }

        do {
            try await FirestoreManager.shared.setCoachNote(
                videoID: videoID,
                text: text,
                authorID: authorID,
                authorName: authorName
            )
        } catch {
            ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayerViewModel.updateCoachNote", showAlert: false)
            throw error
        }

        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            coachNoteText = trimmed
            coachNoteAuthorName = authorName
            coachNoteUpdatedAt = Date()
            // setCoachNote in FirestoreManager also writes reviewedBy.{authorID}
            // — mirror that locally so the Mark as Reviewed button hides
            // immediately without a refetch.
            reviewedAt = Date()

            // Notify the folder owner that a coach left a plain note. Reuses the
            // existing coachComment notification path so the in-app banner +
            // folder badge + per-video "New" badge all light up the same way as
            // a timestamped feedback marker.
            await ActivityNotificationService.shared.postCoachCommentNotification(
                videoFileName: video.fileName,
                folderID: folder.id ?? "",
                videoID: video.id,
                coachID: authorID,
                coachName: authorName,
                athleteID: folder.ownerAthleteID,
                notePreview: trimmed
            )
        } else {
            coachNoteText = nil
            coachNoteAuthorName = nil
            coachNoteUpdatedAt = nil
            // Clearing the note does NOT undo the reviewed state — once
            // reviewed, stay reviewed.
        }
        Haptics.success()
    }

    /// Returns true iff `coachID` has reviewed this clip — either locally in
    /// this view session, or persisted in `video.reviewedBy`.
    func isReviewed(by coachID: String) -> Bool {
        if reviewedAt != nil { return true }
        return video.isReviewed(by: coachID)
    }

    /// Explicitly mark the clip reviewed by the current coach. Throws so the
    /// caller can surface the error inline.
    func markReviewed(coachID: String) async throws {
        let videoID = video.id
        guard !videoID.isEmpty else { return }
        do {
            try await FirestoreManager.shared.markVideoReviewedByCoach(
                videoID: videoID,
                coachID: coachID
            )
        } catch {
            ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayerViewModel.markReviewed", showAlert: false)
            throw error
        }
        reviewedAt = Date()
        Haptics.success()
    }

    func deleteAnnotation(_ annotation: VideoAnnotation) async {
        do {
            let videoID = video.id
            guard !videoID.isEmpty,
                  let annotationID = annotation.id else { return }

            try await FirestoreManager.shared.deleteAnnotation(videoID: videoID, annotationID: annotationID)
            // Listener will drop the deleted annotation on next snapshot.
            Haptics.success()
        } catch {
            errorMessage = "Failed to delete feedback: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayerViewModel.deleteAnnotation", showAlert: false)
        }
    }

    // MARK: - Playback Control

    func startTimeObserver() {
        guard let player = player else { return }

        durationTask?.cancel()
        if let currentItem = player.currentItem {
            durationTask = Task {
                do {
                    let duration = try await currentItem.asset.load(.duration)
                    if !Task.isCancelled {
                        self.videoDuration = duration.seconds
                    }
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.loadDuration", showAlert: false)
                }
            }
        }

        let interval = CMTime(seconds: 1.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                let currentRate = Float(self.playbackRate)
                if player.timeControlStatus == .playing, player.rate != currentRate {
                    player.rate = currentRate
                }
            }
        }
    }

    func stopTimeObserver() {
        durationTask?.cancel()
        durationTask = nil
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    func seekToTimestamp(_ timestamp: Double) {
        let time = CMTime(seconds: timestamp, preferredTimescale: 600)
        player?.seek(to: time)
        player?.play()
    }

    /// Seeks to a precise timestamp without auto-playing. Used by the filmstrip
    /// for frame inspection and telestration frame selection.
    func seekToTimestampPaused(_ timestamp: Double) {
        let time = CMTime(seconds: timestamp, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        player?.pause()
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        if player?.timeControlStatus == .playing {
            player?.rate = Float(rate)
        }
    }

    // MARK: - Filmstrip

    /// Generates frame thumbnails for the filmstrip scrubber.
    /// Loads duration from the asset if not already available.
    func generateFilmstrip() {
        guard let currentItem = player?.currentItem else { return }
        let asset = currentItem.asset

        filmstripTask?.cancel()
        isGeneratingFilmstrip = true

        let generator = FilmstripGenerator()
        filmstripTask = Task {
            // Ensure duration is available — it may not be loaded yet
            // if generateFilmstrip runs before startTimeObserver fires.
            var duration = videoDuration ?? 0
            if duration <= 0 {
                do {
                    let loaded = try await asset.load(.duration)
                    duration = loaded.seconds
                    if !Task.isCancelled {
                        videoDuration = duration
                    }
                } catch {
                    isGeneratingFilmstrip = false
                    return
                }
            }
            guard duration > 0, !Task.isCancelled else {
                isGeneratingFilmstrip = false
                return
            }

            await generator.generateThumbnails(
                for: asset,
                duration: duration,
                onProgress: { [weak self] thumbnails in
                    self?.filmstripThumbnails = thumbnails
                }
            )
            if !Task.isCancelled {
                isGeneratingFilmstrip = false
            }
        }
    }

    /// Starts a high-frequency time observer (0.1s) for filmstrip tracking.
    /// Call when the filmstrip becomes visible; pair with `stopFilmstripTimeObserver`.
    func startFilmstripTimeObserver() {
        guard let player, filmstripTimeObserver == nil else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        filmstripTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            MainActor.assumeIsolated {
                let newTime = time.seconds
                // Throttle: only update if changed by more than 0.05s
                if abs(newTime - self.observedPlaybackTime) > 0.05 {
                    self.observedPlaybackTime = newTime
                }
            }
        }
    }

    /// Removes the filmstrip time observer. Call when the filmstrip is hidden.
    func stopFilmstripTimeObserver() {
        if let observer = filmstripTimeObserver {
            player?.removeTimeObserver(observer)
            filmstripTimeObserver = nil
        }
    }

    /// Loads the video's natural size for aspect-ratio–correct telestration canvas.
    func loadVideoNaturalSize() async {
        guard let asset = player?.currentItem?.asset else { return }
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let transformed = size.applying(transform)
                videoNaturalSize = CGSize(
                    width: abs(transformed.width),
                    height: abs(transformed.height)
                )
            }
        } catch {
            // Fall back to 16:9 if we can't determine
            videoNaturalSize = CGSize(width: 16, height: 9)
        }
    }

    // MARK: - Telestration

    /// Saves a PencilKit drawing as a "drawing" annotation at the given timestamp.
    /// Returns `true` on success so the caller can dismiss the overlay.
    @discardableResult
    func addDrawingAnnotation(
        drawing: PKDrawing,
        timestamp: Double,
        canvasSize: CGSize,
        userID: String,
        userName: String
    ) async -> Bool {
        // Enforce size limit (~200KB pre-encoding) before encoding to base64
        let rawData = drawing.dataRepresentation()
        guard rawData.count <= 200_000 else {
            errorMessage = "Drawing is too complex. Try simplifying and saving again."
            return false
        }

        let base64 = rawData.base64EncodedString()

        do {
            let videoID = video.id
            guard !videoID.isEmpty else { return false }

            let annotation = try await FirestoreManager.shared.createAnnotation(
                videoID: videoID,
                text: "Drawing annotation",
                timestamp: timestamp,
                userID: userID,
                userName: userName,
                isCoachComment: true,
                type: "drawing",
                drawingData: base64,
                drawingCanvasWidth: canvasSize.width > 0 ? Double(canvasSize.width) : nil,
                drawingCanvasHeight: canvasSize.height > 0 ? Double(canvasSize.height) : nil
            )

            // Live listener drives `annotations` — skip local append to avoid flash.
            _ = annotation
            Haptics.success()

            // Notify the folder owner that the coach left a drawing
            await ActivityNotificationService.shared.postCoachCommentNotification(
                videoFileName: video.fileName,
                folderID: folder.id ?? "",
                videoID: videoID,
                coachID: userID,
                coachName: userName,
                athleteID: folder.ownerAthleteID,
                notePreview: "Drawing annotation"
            )
            return true
        } catch {
            errorMessage = "Failed to save drawing: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayerViewModel.addDrawingAnnotation", showAlert: false)
            return false
        }
    }

    /// Shows a saved drawing overlay on the video. Seeks to the annotation's
    /// timestamp and pauses playback.
    func showDrawingOverlay(for annotation: VideoAnnotation) {
        guard let data = annotation.drawingPKData else { return }
        seekToTimestampPaused(annotation.timestamp)
        let size: CGSize? = {
            guard let w = annotation.drawingCanvasWidth,
                  let h = annotation.drawingCanvasHeight,
                  w > 0, h > 0 else { return nil }
            return CGSize(width: w, height: h)
        }()
        activeDrawingOverlay = ActiveDrawingOverlay(data: data, canvasSize: size)
    }

    /// Dismisses the drawing overlay.
    func dismissDrawingOverlay() {
        activeDrawingOverlay = nil
    }

    // MARK: - Save to Photos

    func saveToPhotos() async {
        isSaving = true
        saveError = nil
        didSaveSuccessfully = false

        let cache = CoachVideoCacheService.shared
        let folderID = folder.id ?? ""

        // Get or download the file
        let fileURL: URL
        if let cachedURL = cache.cachedURL(folderID: folderID, fileName: video.fileName) {
            fileURL = cachedURL
        } else {
            do {
                let signedURL = try await SecureURLManager.shared.getSecureVideoURL(
                    fileName: video.fileName,
                    folderID: folderID
                )
                fileURL = try await cache.downloadAndCache(
                    signedURLString: signedURL,
                    folderID: folderID,
                    fileName: video.fileName
                )
            } catch {
                saveError = "Failed to download video: \(error.localizedDescription)"
                isSaving = false
                return
            }
        }

        // Request Photos permission and save
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveError = "Photo library access is required to save videos. Please enable it in Settings."
            isSaving = false
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
            didSaveSuccessfully = true
            Haptics.success()
        } catch {
            saveError = "Failed to save video: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
