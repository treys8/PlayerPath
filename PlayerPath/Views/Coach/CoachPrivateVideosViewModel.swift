//
//  CoachPrivateVideosViewModel.swift
//  PlayerPath
//
//  ViewModel for the "My Recordings" tab. Manages coach's private
//  instruction videos staged for review before sharing with athletes.
//  All data lives in the unified `videos` collection with visibility: "private".
//

import SwiftUI
import Combine
import FirebaseAuth

@MainActor
class CoachPrivateVideosViewModel: ObservableObject {
    @Published var videos: [FirestoreVideoMetadata] = []
    @Published var isLoading = false
    @Published var isUploading = false
    @Published var isPublishing = false
    @Published var errorMessage: String?

    private var coachID: String?
    private var coachName: String?
    private var sharedFolderID: String?
    private let firestore = FirestoreManager.shared

    func setup(coachID: String, sharedFolderID: String) async {
        self.coachID = coachID
        self.sharedFolderID = sharedFolderID
        self.coachName = Auth.auth().currentUser?.displayName
            ?? Auth.auth().currentUser?.email
            ?? "Coach"
        await loadVideos()
    }

    func loadVideos() async {
        guard let coachID, let sharedFolderID else { return }
        isLoading = true
        do {
            videos = try await firestore.fetchCoachPrivateVideos(
                coachID: coachID,
                sharedFolderID: sharedFolderID
            )
        } catch {
            errorMessage = "Failed to load recordings: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachPrivateVideosViewModel.loadVideos", showAlert: false)
        }
        isLoading = false
    }

    func uploadRecording(videoURL: URL) async {
        guard let sharedFolderID,
              let coachID,
              let coachName else { return }

        isUploading = true

        do {
            let dateStr = Date().formatted(.iso8601.year().month().day())
            let fileName = "instruction_\(dateStr)_\(UUID().uuidString.prefix(8)).mov"

            let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            // Upload video to Storage
            let storageURL = try await VideoCloudManager.shared.uploadVideo(
                localURL: videoURL,
                fileName: fileName,
                folderID: sharedFolderID,
                progressHandler: { _ in }
            )

            // Process: extract duration + generate/upload thumbnail
            let processed = await CoachVideoProcessingService.shared.process(
                videoURL: videoURL,
                fileName: fileName,
                folderID: sharedFolderID
            )

            // Save metadata to unified videos collection with visibility: "private"
            _ = try await firestore.uploadVideoMetadata(
                fileName: fileName,
                storageURL: storageURL,
                thumbnail: processed.thumbnailURL.map { ThumbnailMetadata(standardURL: $0) },
                folderID: sharedFolderID,
                uploadedBy: coachID,
                uploadedByName: coachName,
                fileSize: fileSize,
                duration: processed.duration,
                videoType: "instruction",
                uploadedByType: .coach,
                visibility: "private"
            )

            Haptics.success()
            await loadVideos()
        } catch {
            errorMessage = "Failed to save recording: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachPrivateVideosViewModel.uploadRecording", showAlert: false)
        }

        isUploading = false
    }

    func publishVideo(_ video: FirestoreVideoMetadata, notes: String? = nil, tags: [String] = [], drillType: String? = nil) async {
        guard let videoID = video.id,
              let sharedFolderID else {
            errorMessage = "Unable to share video. Please try again."
            return
        }

        isPublishing = true

        do {
            try await firestore.publishPrivateVideo(
                videoID: videoID,
                sharedFolderID: sharedFolderID,
                notes: notes,
                tags: tags.isEmpty ? nil : tags,
                drillType: drillType
            )
            Haptics.success()
            await loadVideos()
        } catch {
            errorMessage = "Failed to share video: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachPrivateVideosViewModel.publishVideo", showAlert: false)
        }

        isPublishing = false
    }

    func deleteVideo(_ video: FirestoreVideoMetadata) async {
        guard let videoID = video.id,
              let sharedFolderID else { return }

        do {
            try await firestore.deleteCoachPrivateVideo(
                videoID: videoID,
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
