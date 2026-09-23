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

    /// True when the last refresh had at least one folder fetch fail. Without this a
    /// network failure is indistinguishable from an empty queue: the dashboard card
    /// is gated on `totalCount > 0`, so failures silently render as "nothing to
    /// review" on the app's primary coach value prop.
    private(set) var lastRefreshFailed = false

    /// Per-folder fetch cap. A coach with 30 folders × 50 clips = 1500 reads
    /// in the worst case on a cold dashboard load — typical case is far less.
    private static let perFolderLimit = 50

    private init() {}

    /// Sign-out teardown — this singleton otherwise carries one coach's queue into
    /// the next account signed in on the same device.
    func reset() {
        groupedClips = []
        lastRefreshFailed = false
        isLoading = false
    }

    /// Refreshes the queue. Fetches all relevant videos from each folder in
    /// parallel, filters client-side, and rebuilds the grouped list.
    func refresh(coachUID: String, folders: [SharedFolder]) async {
        guard !coachUID.isEmpty else {
            groupedClips = []
            lastRefreshFailed = false
            return
        }
        isLoading = true
        defer { isLoading = false }

        let db = Firestore.firestore()
        let folderIDs = folders.compactMap(\.id)

        // Fetch every folder's recent shared videos in parallel.
        let (perFolderResults, anyFolderFailed): ([(folderID: String, items: [CoachVideoItem])], Bool) = await withTaskGroup(
            of: (String, [CoachVideoItem], Bool).self
        ) { group in
            for folderID in folderIDs {
                group.addTask {
                    let result = await Self.fetchUnreviewed(
                        db: db,
                        folderID: folderID,
                        coachUID: coachUID
                    )
                    return (folderID, result.items, result.failed)
                }
            }
            var collected: [(String, [CoachVideoItem])] = []
            var failed = false
            for await (folderID, items, didFail) in group {
                if didFail { failed = true }
                if !items.isEmpty { collected.append((folderID, items)) }
            }
            return (collected, failed)
        }
        lastRefreshFailed = anyFolderFailed

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

        // Keep the daily review reminder honest: it is a repeating local
        // notification whose body claims clips are waiting, so it must not stay
        // armed once the queue is empty. A failed refresh leaves it alone —
        // `groupedClips` is empty then too, and disarming on a network blip
        // would silently stop a coach's reminders.
        if !lastRefreshFailed {
            await PushNotificationService.shared.syncReviewReminder(pendingCount: totalCount)
        }
    }

    /// Single-folder fetch + client-side filter. Static so the TaskGroup
    /// closure doesn't capture `self` from the @MainActor context.
    /// - Returns: the matching clips, plus whether the FETCH failed. Per-document
    ///   decode failures are skipped without setting `failed` — only losing the whole
    ///   folder counts, since that's what makes an empty queue a lie.
    private static func fetchUnreviewed(
        db: Firestore,
        folderID: String,
        coachUID: String
    ) async -> (items: [CoachVideoItem], failed: Bool) {
        do {
            let snapshot = try await db.collection("videos")
                .whereField("sharedFolderID", isEqualTo: folderID)
                .order(by: "createdAt", descending: true)
                .limit(to: perFolderLimit)
                .getDocuments()

            let items = snapshot.documents.compactMap { doc -> CoachVideoItem? in
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
            return (items, false)
        } catch {
            needsReviewLog.warning("Folder fetch failed for \(folderID): \(error.localizedDescription)")
            return ([], true)
        }
    }
}
