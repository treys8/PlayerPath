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
    /// Set when the real-time listener encounters an error; views can show a
    /// "showing cached data" banner when non-nil.
    var listenerError: String?

    // Filtered views derived from `videos`. Computed so they stay in sync
    // automatically — no manual cache-refresh step after every mutation.
    // @Observable tracks reads through these since they access `videos`.

    /// Games folder: all visible videos (uploaded by athlete, or shared coach clips).
    var allVideos: [CoachVideoItem] {
        videos.filter { $0.visibility != "private" }
    }

    /// Games folder: athlete clips this coach hasn't yet reviewed.
    var needsReviewVideos: [CoachVideoItem] {
        let myUID = currentUserID ?? ""
        return allVideos.filter { v in
            v.uploadedBy != myUID && !v.isReviewed(by: myUID)
        }
    }

    /// Lessons folder: coach's private clips pending review.
    var reviewVideos: [CoachVideoItem] {
        let myUID = currentUserID ?? ""
        return videos.filter { $0.visibility == "private" && $0.uploadedBy == myUID }
    }

    /// Lessons folder: coach's published clips.
    var sharedVideos: [CoachVideoItem] {
        let myUID = currentUserID ?? ""
        return allVideos.filter { $0.uploadedBy == myUID }
    }

    var reviewCount: Int { reviewVideos.count }
    var needsReviewCount: Int { needsReviewVideos.count }

    /// Athlete tab: game-type videos (takes priority over instruction for dual-tagged clips).
    var gameVideos: [CoachVideoItem] {
        allVideos.filter { $0.videoType == "game" || $0.gameOpponent != nil }
    }

    /// Athlete tab: instruction/practice videos. Excludes any clip already classified as a game.
    var instructionVideos: [CoachVideoItem] {
        let gameIDs = Set(gameVideos.map(\.id))
        return allVideos.filter { !gameIDs.contains($0.id) && ($0.videoType == "instruction" || $0.videoType == "practice" || $0.practiceDate != nil) }
    }

    private var prefetchedFileNames: Set<String> = []
    private var lastVideoDocument: QueryDocumentSnapshot?
    private static let pageSize = 30
    // @ObservationIgnored so the @Observable macro doesn't wrap this in
    // @ObservationTracked, which would make the nonisolated(unsafe) marker
    // invalid. nonisolated(unsafe) lets deinit call .remove() on the listener.
    @ObservationIgnored
    nonisolated(unsafe) private var videosListener: ListenerRegistration?

    init(folder: SharedFolder) {
        self.folder = folder
    }

    deinit {
        videosListener?.remove()
    }

    private var currentUserID: String? { Auth.auth().currentUser?.uid }

    /// Processes a list of Firestore video metadata into the view's video arrays.
    private func applyVideos(_ firestoreVideos: [FirestoreVideoMetadata]) {
        let currentUID = Auth.auth().currentUser?.uid
        videos = firestoreVideos
            .filter { $0.visibility != "private" || $0.uploadedBy == currentUID }
            .map { CoachVideoItem(from: $0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
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
        let listener = FirestoreManager.shared.listenToVideos(
            forFolder: folderID,
            onChange: { [weak self] firestoreVideos in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.listenerError = nil
                    self.mergeListenerVideos(firestoreVideos)
                    self.prefetchURLs(folderID: folderID)
                }
            },
            onError: { [weak self] _ in
                Task { @MainActor in
                    self?.listenerError = "Unable to refresh videos. Showing cached data."
                }
            }
        )
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
