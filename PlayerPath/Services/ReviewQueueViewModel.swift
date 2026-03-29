//
//  ReviewQueueViewModel.swift
//  PlayerPath
//
//  Aggregates all private (unreviewed) coach clips across all shared folders
//  into a single review queue. Used by the coach dashboard.
//

import SwiftUI
import FirebaseFirestore
import os

private let reviewLog = Logger(subsystem: "com.playerpath.app", category: "ReviewQueue")

// MARK: - Athlete Clip Group

struct AthleteClipGroup: Identifiable {
    var id: String { folderID }
    let athleteName: String
    let athleteID: String
    let folderID: String
    let folder: SharedFolder?
    let clips: [CoachVideoItem]
}

// MARK: - Review Queue View Model

@MainActor
@Observable
class ReviewQueueViewModel {
    static let shared = ReviewQueueViewModel()

    var isLoading = false

    /// Total unreviewed clips.
    var totalCount: Int { cachedClips.count }

    /// Clips grouped by athlete/folder, each group sorted newest-first.
    private(set) var groupedClips: [AthleteClipGroup] = []

    /// Raw clips from the Firestore listener. Setting this recomputes groupedClips.
    private var cachedClips: [CoachVideoItem] = [] {
        didSet { rebuildGroupedClips() }
    }

    private func rebuildGroupedClips() {
        let folders = SharedFolderManager.shared.coachFolders
        let grouped = Dictionary(grouping: cachedClips) { $0.sharedFolderID }

        groupedClips = grouped.compactMap { folderID, folderClips in
            let folder = folders.first { $0.id == folderID }
            let athleteName = folder?.ownerAthleteName ?? "Athlete"
            let athleteID = folder?.ownerAthleteID ?? ""
            return AthleteClipGroup(
                athleteName: athleteName,
                athleteID: athleteID,
                folderID: folderID,
                folder: folder,
                clips: folderClips.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            )
        }
        .sorted { $0.athleteName.localizedCaseInsensitiveCompare($1.athleteName) == .orderedAscending }
    }

    // nonisolated(unsafe) so deinit can call .remove() on the listener
    nonisolated(unsafe) private var listener: ListenerRegistration?
    private var listeningCoachUID: String?

    private init() {}

    deinit {
        listener?.remove()
    }

    // MARK: - Listener

    func startListening(coachUID: String) {
        guard listeningCoachUID != coachUID else { return }
        stopListening()
        listeningCoachUID = coachUID
        isLoading = true

        let db = Firestore.firestore()
        listener = db.collection("videos")
            .whereField("uploadedBy", isEqualTo: coachUID)
            .whereField("visibility", isEqualTo: "private")
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false

                    if let error {
                        reviewLog.warning("Review queue listener error: \(error.localizedDescription)")
                        return
                    }

                    guard let docs = snapshot?.documents else { return }
                    self.cachedClips = docs.compactMap { doc -> CoachVideoItem? in
                        do {
                            var video = try doc.data(as: FirestoreVideoMetadata.self)
                            video.id = doc.documentID
                            // Filter out clips still uploading
                            if let status = video.uploadStatus, status != "completed" {
                                return nil
                            }
                            return CoachVideoItem(from: video)
                        } catch {
                            reviewLog.warning("Failed to decode review clip \(doc.documentID): \(error.localizedDescription)")
                            return nil
                        }
                    }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        listeningCoachUID = nil
        cachedClips = []
    }

}
