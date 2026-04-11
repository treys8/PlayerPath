//
//  NeedsReviewQueueViewModel.swift
//  PlayerPath
//
//  Aggregates athlete-shared clips across all of the coach's folders that
//  the coach hasn't yet reviewed. Used by the coach dashboard's "Needs Your
//  Review" card. Fetch-based (not a snapshot listener) to keep idle Firestore
//  reads down — refreshed on dashboard appear and on pull-to-refresh.
//

import SwiftUI
import FirebaseFirestore
import os

private let needsReviewLog = Logger(subsystem: "com.playerpath.app", category: "NeedsReviewQueue")

@MainActor
@Observable
class NeedsReviewQueueViewModel {
    static let shared = NeedsReviewQueueViewModel()

    var isLoading = false

    /// Total clips waiting for the coach across all folders.
    var totalCount: Int {
        groupedClips.reduce(0) { $0 + $1.clips.count }
    }

    /// Clips grouped by folder/athlete, each group sorted newest-first,
    /// the groups themselves sorted alphabetically by athlete name. Reuses
    /// `AthleteClipGroup` from `ReviewQueueViewModel`.
    private(set) var groupedClips: [AthleteClipGroup] = []

    /// Per-folder fetch cap. A coach with 30 folders × 50 clips = 1500 reads
    /// in the worst case on a cold dashboard load — typical case is far less.
    private static let perFolderLimit = 50

    private init() {}

    /// Refreshes the queue. Fetches all relevant videos from each folder in
    /// parallel, filters client-side, and rebuilds the grouped list.
    func refresh(coachUID: String, folders: [SharedFolder]) async {
        guard !coachUID.isEmpty else {
            groupedClips = []
            return
        }
        isLoading = true
        defer { isLoading = false }

        let db = Firestore.firestore()
        let folderIDs = folders.compactMap(\.id)

        // Fetch every folder's recent shared videos in parallel.
        let perFolderResults: [(folderID: String, items: [CoachVideoItem])] = await withTaskGroup(of: (String, [CoachVideoItem]).self) { group in
            for folderID in folderIDs {
                group.addTask {
                    let items = await Self.fetchUnreviewed(
                        db: db,
                        folderID: folderID,
                        coachUID: coachUID
                    )
                    return (folderID, items)
                }
            }
            var collected: [(String, [CoachVideoItem])] = []
            for await (folderID, items) in group where !items.isEmpty {
                collected.append((folderID, items))
            }
            return collected
        }

        // Group results into AthleteClipGroup, attaching folder metadata.
        let folderByID: [String: SharedFolder] = Dictionary(uniqueKeysWithValues: folders.compactMap { f in
            f.id.map { ($0, f) }
        })

        groupedClips = perFolderResults.map { folderID, items in
            let folder = folderByID[folderID]
            return AthleteClipGroup(
                athleteName: folder?.ownerAthleteName ?? "Athlete",
                athleteID: folder?.ownerAthleteID ?? "",
                folderID: folderID,
                folder: folder,
                clips: items.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            )
        }
        .sorted { $0.athleteName.localizedCaseInsensitiveCompare($1.athleteName) == .orderedAscending }
    }

    /// Single-folder fetch + client-side filter. Static so the TaskGroup
    /// closure doesn't capture `self` from the @MainActor context.
    private static func fetchUnreviewed(
        db: Firestore,
        folderID: String,
        coachUID: String
    ) async -> [CoachVideoItem] {
        do {
            let snapshot = try await db.collection("videos")
                .whereField("sharedFolderID", isEqualTo: folderID)
                .order(by: "createdAt", descending: true)
                .limit(to: perFolderLimit)
                .getDocuments()

            return snapshot.documents.compactMap { doc -> CoachVideoItem? in
                do {
                    var meta = try doc.data(as: FirestoreVideoMetadata.self)
                    meta.id = doc.documentID

                    // Skip private drafts and in-flight uploads.
                    if meta.visibility == "private" { return nil }
                    if let status = meta.uploadStatus, status != "completed" { return nil }
                    // Skip clips the coach uploaded themselves.
                    if meta.uploadedBy == coachUID { return nil }
                    // Skip clips already reviewed by this coach.
                    if meta.reviewedBy?[coachUID] != nil { return nil }

                    return CoachVideoItem(from: meta)
                } catch {
                    needsReviewLog.warning("Failed to decode video \(doc.documentID): \(error.localizedDescription)")
                    return nil
                }
            }
        } catch {
            needsReviewLog.warning("Folder fetch failed for \(folderID): \(error.localizedDescription)")
            return []
        }
    }
}
