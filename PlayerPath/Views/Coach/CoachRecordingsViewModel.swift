//
//  CoachRecordingsViewModel.swift
//  PlayerPath
//
//  ViewModel for the coach Recordings tab.
//  Fetches all private instruction videos across all athletes
//  from the unified `videos` collection.
//

import SwiftUI
import Combine
import FirebaseAuth

// MARK: - Models

struct CoachRecordingItem: Identifiable {
    var id: String { metadata.id ?? UUID().uuidString }
    let metadata: FirestoreVideoMetadata
    let athleteName: String
    let folderName: String
    let sharedFolderID: String
}

struct CoachRecordingGroup {
    let date: Date
    let recordings: [CoachRecordingItem]
}

// MARK: - View Model

@MainActor
class CoachRecordingsViewModel: ObservableObject {
    @Published var groupedRecordings: [CoachRecordingGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let firestore = FirestoreManager.shared

    func loadAllRecordings(coachID: String, folders: [SharedFolder]) async {
        isLoading = true

        do {
            // Single query: all private videos for this coach across all folders
            let allVideos = try await firestore.fetchCoachPrivateVideos(coachID: coachID)

            // Build items by matching each video's sharedFolderID to a folder
            let folderMap = Dictionary(uniqueKeysWithValues: folders.compactMap { folder in
                folder.id.map { ($0, folder) }
            })

            let items: [CoachRecordingItem] = allVideos.compactMap { video in
                let folderID = video.sharedFolderID
                guard let folder = folderMap[folderID] else {
                    return nil
                }
                return CoachRecordingItem(
                    metadata: video,
                    athleteName: folder.ownerAthleteName ?? "Unknown Athlete",
                    folderName: folder.name,
                    sharedFolderID: folderID
                )
            }

            // Group by day
            let calendar = Calendar.current
            let grouped = Dictionary(grouping: items) { item -> Date in
                calendar.startOfDay(for: item.metadata.createdAt ?? Date())
            }

            groupedRecordings = grouped
                .sorted { $0.key > $1.key }
                .map { CoachRecordingGroup(date: $0.key, recordings: $0.value) }

        } catch {
            errorMessage = "Failed to load recordings: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachRecordingsViewModel.loadAllRecordings", showAlert: false)
        }

        isLoading = false
    }

    func deleteVideo(_ item: CoachRecordingItem) async {
        guard let videoID = item.metadata.id else { return }
        do {
            try await firestore.deleteCoachPrivateVideo(
                videoID: videoID,
                sharedFolderID: item.sharedFolderID,
                fileName: item.metadata.fileName
            )
            Haptics.success()
            removeFromLocalState(videoID: videoID)
        } catch {
            errorMessage = "Failed to delete recording: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachRecordingsViewModel.deleteVideo", showAlert: false)
        }
    }

    func publishVideo(_ item: CoachRecordingItem, notes: String? = nil, tags: [String] = [], drillType: String? = nil) async {
        guard let videoID = item.metadata.id else { return }
        do {
            try await firestore.publishPrivateVideo(
                videoID: videoID,
                sharedFolderID: item.sharedFolderID,
                notes: notes,
                tags: tags.isEmpty ? nil : tags,
                drillType: drillType
            )
            Haptics.success()
            removeFromLocalState(videoID: videoID)
        } catch {
            errorMessage = "Failed to share video: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachRecordingsViewModel.publishVideo", showAlert: false)
        }
    }

    private func removeFromLocalState(videoID: String) {
        for i in groupedRecordings.indices {
            groupedRecordings[i] = CoachRecordingGroup(
                date: groupedRecordings[i].date,
                recordings: groupedRecordings[i].recordings.filter { $0.id != videoID }
            )
        }
        groupedRecordings.removeAll { $0.recordings.isEmpty }
    }
}
