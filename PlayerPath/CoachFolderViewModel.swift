//
//  CoachFolderViewModel.swift
//  PlayerPath
//
//  Extracted from CoachFolderDetailView.swift
//  Migrated from ObservableObject to @Observable per project convention.
//

import SwiftUI
import FirebaseAuth

@MainActor
@Observable
class CoachFolderViewModel {
    let folder: SharedFolder

    var videos: [CoachVideoItem] = []
    var isLoading = false
    var errorMessage: String?

    /// Cached filtered arrays — updated whenever `videos` changes
    // Coach tabs
    var cachedFromAthleteVideos: [CoachVideoItem] = []
    var cachedNeedsReviewVideos: [CoachVideoItem] = []
    var cachedFromMeVideos: [CoachVideoItem] = []

    var needsReviewCount: Int { cachedNeedsReviewVideos.count }
    // Athlete tabs (used by AthleteFoldersListView)
    var cachedGameVideos: [CoachVideoItem] = []
    var cachedInstructionVideos: [CoachVideoItem] = []

    init(folder: SharedFolder) {
        self.folder = folder
    }

    private var currentUserID: String? { Auth.auth().currentUser?.uid }

    private func updateFilteredVideos() {
        let myUID = currentUserID ?? ""
        let sharedVideos = videos.filter { $0.visibility != "private" }

        // Coach: From Athlete / Needs Review / From Me
        cachedFromAthleteVideos = sharedVideos.filter { $0.uploadedBy != myUID }
        cachedNeedsReviewVideos = videos.filter { $0.visibility == "private" && $0.uploadedBy == myUID }
        cachedFromMeVideos = sharedVideos.filter { $0.uploadedBy == myUID }

        // Athlete: Games / Instruction
        cachedGameVideos = sharedVideos.filter { $0.videoType == "game" || $0.gameOpponent != nil }
        cachedInstructionVideos = sharedVideos.filter { $0.videoType == "instruction" || $0.videoType == "practice" || ($0.practiceDate != nil && $0.gameOpponent == nil) }
    }

    func loadVideos() async {
        isLoading = true
        defer { isLoading = false }

        guard let folderID = folder.id else {
            errorMessage = "Invalid folder"
            return
        }

        do {
            let firestoreVideos = try await FirestoreManager.shared.fetchVideos(forSharedFolder: folderID)

            // Convert to CoachVideoItem, filtering out other coaches' private videos
            let currentUserID = Auth.auth().currentUser?.uid
            videos = firestoreVideos
                .filter { video in
                    // Show: shared videos, own private videos, legacy videos (no visibility)
                    video.visibility != "private" || video.uploadedBy == currentUserID
                }
                .map { CoachVideoItem(from: $0) }
                .sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
            updateFilteredVideos()

            // Pre-fetch signed URLs in background so tapping a video
            // doesn't block on a Cloud Function round-trip (200-800ms).
            // The 24-hour expiry makes this safe to do eagerly.
            let fileNames = videos.map(\.fileName)
            if !fileNames.isEmpty {
                Task {
                    do {
                        _ = try await SecureURLManager.shared.getBatchSecureVideoURLs(
                            fileNames: fileNames,
                            folderID: folderID
                        )
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "CoachFolderDetail.prefetchURLs", showAlert: false)
                    }
                }
            }

        } catch {
            errorMessage = "Failed to load videos: \(error.localizedDescription)"
        }
    }
}
