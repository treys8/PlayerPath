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

    // MARK: - Video Loading

    func loadVideo() async {
        isLoading = true
        isPlayerReady = false

        let playbackURLString: String
        do {
            playbackURLString = try await SecureURLManager.shared.getSecureVideoURL(
                fileName: video.fileName,
                folderID: folder.id ?? ""
            )
        } catch {
            ErrorHandlerService.shared.handle(error, context: "CoachVideoPlayer.getSignedURL", showAlert: false)
            errorMessage = "Unable to load video. Please check your connection and try again."
            isLoading = false
            return
        }

        guard let url = URL(string: playbackURLString) else {
            isLoading = false
            return
        }

        let newPlayer = AVPlayer(url: url)
        player = newPlayer

        statusObservation = nil
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
}
