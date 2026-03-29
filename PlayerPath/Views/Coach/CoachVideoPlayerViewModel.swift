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

    // Download & save state
    var isDownloading = false
    var downloadProgress: Double = 0
    var isSaving = false
    var didSaveSuccessfully = false
    var saveError: String?

    private var durationTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var timeObserver: Any?

    var currentPlaybackTime: Double {
        player?.currentTime().seconds ?? 0.0
    }

    init(video: CoachVideoItem, folder: SharedFolder) {
        self.video = video
        self.folder = folder
    }

    deinit {
        // @MainActor class instances owned by SwiftUI views are deallocated
        // on the main thread, so assumeIsolated is safe here.
        MainActor.assumeIsolated {
            durationTask?.cancel()
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
            }
            statusObservation?.invalidate()
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

        let cache = CoachVideoCacheService.shared
        let folderID = folder.id ?? ""
        let playbackURL: URL

        // Check cache first for offline playback
        if let cachedURL = cache.cachedURL(folderID: folderID, fileName: video.fileName) {
            playbackURL = cachedURL
        } else {
            // Fetch signed URL and download to cache
            let signedURLString: String
            do {
                signedURLString = try await SecureURLManager.shared.getSecureVideoURL(
                    fileName: video.fileName,
                    folderID: folderID
                )
            } catch {
                ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.getSignedURL", showAlert: false)
                errorMessage = "Unable to load video. Please check your connection and try again."
                isLoading = false
                return
            }

            // Download and cache for offline use
            isDownloading = true
            do {
                playbackURL = try await cache.downloadAndCache(
                    signedURLString: signedURLString,
                    folderID: folderID,
                    fileName: video.fileName
                )
            } catch let cacheError as CoachVideoCacheError where cacheError == .signedURLExpired {
                // Signed URL expired mid-download — fetch a fresh one and retry once
                isDownloading = false
                do {
                    let freshURL = try await SecureURLManager.shared.getSecureVideoURL(
                        fileName: video.fileName,
                        folderID: folderID,
                        forceRefresh: true
                    )
                    isDownloading = true
                    playbackURL = try await cache.downloadAndCache(
                        signedURLString: freshURL,
                        folderID: folderID,
                        fileName: video.fileName
                    )
                } catch {
                    isDownloading = false
                    if let url = URL(string: signedURLString) {
                        playbackURL = url
                    } else {
                        errorMessage = "Unable to load video."
                        isLoading = false
                        return
                    }
                }
            } catch {
                // Fall back to streaming if download fails
                isDownloading = false
                if let url = URL(string: signedURLString) {
                    playbackURL = url
                } else {
                    errorMessage = "Unable to load video."
                    isLoading = false
                    return
                }
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

        // Log video access (fire-and-forget, don't block playback)
        Task {
            guard let user = Auth.auth().currentUser,
                  let userName = user.displayName else { return }
            let userID = user.uid
            let isOwner = userID == folder.ownerAthleteID
            await FirestoreManager.shared.logVideoAccess(
                videoID: video.id,
                userID: userID,
                userName: userName,
                userRole: isOwner ? "athlete" : "coach",
                action: "view",
                folderID: folderID
            )
        }
    }

    // MARK: - Annotations

    func loadAnnotations() async {
        isLoadingAnnotations = true

        do {
            let videoID = video.id
            guard !videoID.isEmpty else {
                isLoadingAnnotations = false
                return
            }

            annotations = try await FirestoreManager.shared.fetchAnnotations(forVideo: videoID)
                .sorted { $0.timestamp < $1.timestamp }
        } catch {
            // Permission errors are expected for private videos (not yet in shared folder)
            // — annotations don't exist until the video is shared. Don't show error UI.
            let nsError = error as NSError
            if nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7 {
                annotations = []
            } else {
                errorMessage = "Failed to load notes: \(error.localizedDescription)"
            }
        }

        isLoadingAnnotations = false
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

            annotations.append(annotation)
            annotations.sort { $0.timestamp < $1.timestamp }

            // Mirror coach feedback to the unified comment thread
            if isCoachComment {
                do {
                    try await ClipCommentService.shared.postComment(
                        clipId: videoID,
                        text: text,
                        authorId: userID,
                        authorName: userName,
                        authorRole: "coach",
                        category: category
                    )
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
            errorMessage = "Failed to add note: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayerViewModel.addAnnotation", showAlert: false)
        }
    }

    func deleteAnnotation(_ annotation: VideoAnnotation) async {
        do {
            let videoID = video.id
            guard !videoID.isEmpty,
                  let annotationID = annotation.id else { return }

            try await FirestoreManager.shared.deleteAnnotation(videoID: videoID, annotationID: annotationID)
            annotations.removeAll { $0.id == annotationID }
            Haptics.success()
        } catch {
            errorMessage = "Failed to delete note: \(error.localizedDescription)"
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

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        if player?.timeControlStatus == .playing {
            player?.rate = Float(rate)
        }
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

            // Log download action
            if let user = Auth.auth().currentUser {
                let isOwner = user.uid == folder.ownerAthleteID
                await FirestoreManager.shared.logVideoAccess(
                    videoID: video.id,
                    userID: user.uid,
                    userName: user.displayName ?? (isOwner ? "Athlete" : "Coach"),
                    userRole: isOwner ? "athlete" : "coach",
                    action: "download",
                    folderID: folderID
                )
            }
        } catch {
            saveError = "Failed to save video: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
