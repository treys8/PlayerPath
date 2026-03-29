//
//  CoachFolderViewModel.swift
//  PlayerPath
//
//  Extracted from CoachFolderDetailView.swift
//  Migrated from ObservableObject to @Observable per project convention.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
@Observable
class CoachFolderViewModel {
    let folder: SharedFolder

    var videos: [CoachVideoItem] = []
    var isLoading = false
    var isLoadingMore = false
    var hasMoreVideos = false
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

    private var prefetchedFileNames: Set<String> = []
    private var lastVideoDocument: QueryDocumentSnapshot?
    private static let pageSize = 30
    // nonisolated(unsafe) so deinit can call .remove() on the listener
    nonisolated(unsafe) private var videosListener: ListenerRegistration?

    init(folder: SharedFolder) {
        self.folder = folder
    }

    deinit {
        videosListener?.remove()
    }

    private var currentUserID: String? { Auth.auth().currentUser?.uid }

    private func updateFilteredVideos() {
        let myUID = currentUserID ?? ""
        let sharedVideos = videos.filter { $0.visibility != "private" }

        // Coach: From Athlete / Needs Review / From Me
        cachedFromAthleteVideos = sharedVideos.filter { $0.uploadedBy != myUID }
        cachedNeedsReviewVideos = videos.filter { $0.visibility == "private" && $0.uploadedBy == myUID }
        cachedFromMeVideos = sharedVideos.filter { $0.uploadedBy == myUID }

        // Athlete: Games / Instruction (mutually exclusive — games take priority)
        cachedGameVideos = sharedVideos.filter { $0.videoType == "game" || $0.gameOpponent != nil }
        let gameSet = Set(cachedGameVideos.map(\.id))
        cachedInstructionVideos = sharedVideos.filter { !gameSet.contains($0.id) && ($0.videoType == "instruction" || $0.videoType == "practice" || $0.practiceDate != nil) }
    }

    /// Processes a list of Firestore video metadata into the view's video arrays.
    private func applyVideos(_ firestoreVideos: [FirestoreVideoMetadata]) {
        let currentUID = Auth.auth().currentUser?.uid
        videos = firestoreVideos
            .filter { $0.visibility != "private" || $0.uploadedBy == currentUID }
            .map { CoachVideoItem(from: $0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        updateFilteredVideos()
    }

    /// Appends additional videos from a "Load More" page.
    private func appendVideos(_ firestoreVideos: [FirestoreVideoMetadata]) {
        let currentUID = Auth.auth().currentUser?.uid
        let newItems = firestoreVideos
            .filter { $0.visibility != "private" || $0.uploadedBy == currentUID }
            .map { CoachVideoItem(from: $0) }
        let existingIDs = Set(videos.map(\.id))
        let deduplicated = newItems.filter { !existingIDs.contains($0.id) }
        videos.append(contentsOf: deduplicated)
        videos.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        updateFilteredVideos()
    }

    /// Prefetches signed URLs only for videos not already prefetched.
    private func prefetchURLs(folderID: String) {
        let newFileNames = videos.map(\.fileName).filter { !prefetchedFileNames.contains($0) }
        guard !newFileNames.isEmpty else { return }
        prefetchedFileNames.formUnion(newFileNames)
        Task { [weak self] in
            guard self != nil else { return }
            do {
                _ = try await SecureURLManager.shared.getBatchSecureVideoURLs(
                    fileNames: newFileNames,
                    folderID: folderID
                )
            } catch {
                ErrorHandlerService.shared.handle(error, context: "CoachFolderDetail.prefetchURLs", showAlert: false)
            }
        }
    }

    /// Starts a snapshot listener if one isn't already running.
    /// The listener sees the newest 30 videos. When it fires, we merge those with
    /// any additional videos the user loaded via "Load More" so pagination isn't lost.
    private func ensureListening(folderID: String) {
        guard videosListener == nil else { return }
        let listener = FirestoreManager.shared.listenToVideos(forFolder: folderID) { [weak self] firestoreVideos in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mergeListenerVideos(firestoreVideos)
                self.prefetchURLs(folderID: folderID)
            }
        }
        videosListener = listener
    }

    /// Merges the listener's newest 30 videos with any extra videos loaded via pagination.
    private func mergeListenerVideos(_ firestoreVideos: [FirestoreVideoMetadata]) {
        let currentUID = Auth.auth().currentUser?.uid
        let listenerItems = firestoreVideos
            .filter { $0.visibility != "private" || $0.uploadedBy == currentUID }
            .map { CoachVideoItem(from: $0) }
        let listenerIDs = Set(listenerItems.map(\.id))

        // Keep any paginated videos that aren't in the listener's window
        let paginatedExtras = videos.filter { !listenerIDs.contains($0.id) }

        videos = (listenerItems + paginatedExtras)
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        updateFilteredVideos()
    }

    func loadVideos() async {
        isLoading = true
        defer { isLoading = false }

        guard let folderID = folder.id else {
            errorMessage = "Invalid folder"
            return
        }

        guard ConnectivityMonitor.shared.isConnected else {
            if videos.isEmpty {
                errorMessage = "You're offline. Connect to the internet to load videos."
            }
            return
        }

        do {
            let result = try await FirestoreManager.shared.fetchVideoPage(
                forFolder: folderID,
                pageSize: Self.pageSize
            )
            errorMessage = nil
            lastVideoDocument = result.lastDocument
            hasMoreVideos = result.videos.count >= Self.pageSize
            applyVideos(result.videos)
            prefetchURLs(folderID: folderID)

            // After the first successful load, start listening for real-time updates.
            // The listener's first callback will fire with current data (a no-op since
            // we just fetched), then subsequent callbacks deliver live changes.
            ensureListening(folderID: folderID)

        } catch {
            errorMessage = "Failed to load videos: \(error.localizedDescription)"
        }
    }

    func loadMoreVideos() async {
        guard hasMoreVideos, !isLoadingMore, let folderID = folder.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await FirestoreManager.shared.fetchVideoPage(
                forFolder: folderID,
                pageSize: Self.pageSize,
                afterDocument: lastVideoDocument
            )
            lastVideoDocument = result.lastDocument
            hasMoreVideos = result.videos.count >= Self.pageSize
            appendVideos(result.videos)
            prefetchURLs(folderID: folderID)
        } catch {
            ErrorHandlerService.shared.handle(error, context: "CoachFolderViewModel.loadMoreVideos", showAlert: false)
        }
    }
}
