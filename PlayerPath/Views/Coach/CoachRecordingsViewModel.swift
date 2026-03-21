//
//  CoachRecordingsViewModel.swift
//  PlayerPath
//
//  ViewModel and models for the coach Recordings tab.
//  Fetches all private recordings across athletes, grouped by date.
//

import SwiftUI
import Combine
import FirebaseAuth

// MARK: - Models

struct CoachRecordingItem: Identifiable {
    var id: String { video.id ?? UUID().uuidString }
    let video: CoachPrivateVideo
    let athleteName: String
    let folderName: String
    let sharedFolderID: String
    let privateFolderID: String
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
        var allItems: [CoachRecordingItem] = []

        for folder in folders {
            guard let folderID = folder.id else { continue }
            let privateFolderID = "\(coachID)_\(folderID)"

            do {
                let videos = try await firestore.fetchPrivateVideos(privateFolderID: privateFolderID)
                let items = videos.map { video in
                    CoachRecordingItem(
                        video: video,
                        athleteName: folder.ownerAthleteName ?? "Unknown Athlete",
                        folderName: folder.name,
                        sharedFolderID: folderID,
                        privateFolderID: privateFolderID
                    )
                }
                allItems.append(contentsOf: items)
            } catch {
                continue
            }
        }

        allItems.sort { ($0.video.createdAt ?? .distantPast) > ($1.video.createdAt ?? .distantPast) }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allItems) { item -> Date in
            calendar.startOfDay(for: item.video.createdAt ?? Date())
        }

        groupedRecordings = grouped
            .sorted { $0.key > $1.key }
            .map { CoachRecordingGroup(date: $0.key, recordings: $0.value) }

        isLoading = false
    }

    func deleteVideo(_ item: CoachRecordingItem) async {
        guard let videoID = item.video.id else { return }
        do {
            try await firestore.deletePrivateVideo(
                videoID: videoID,
                privateFolderID: item.privateFolderID,
                sharedFolderID: item.sharedFolderID,
                fileName: item.video.fileName
            )
            Haptics.success()
            removeFromLocalState(videoID: videoID)
        } catch {
            errorMessage = "Failed to delete recording: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachRecordingsViewModel.deleteVideo", showAlert: false)
        }
    }

    func moveToSharedFolder(_ item: CoachRecordingItem, tags: [String] = [], drillType: String? = nil) async {
        guard let videoID = item.video.id,
              let coachID = Auth.auth().currentUser?.uid else {
            errorMessage = "Not authenticated. Please sign in again."
            return
        }
        let coachName = Auth.auth().currentUser?.displayName
            ?? Auth.auth().currentUser?.email
            ?? "Coach"

        do {
            try await firestore.moveVideoToSharedFolder(
                privateVideoID: videoID,
                privateFolderID: item.privateFolderID,
                sharedFolderID: item.sharedFolderID,
                coachID: coachID,
                coachName: coachName,
                tags: tags,
                drillType: drillType
            )
            Haptics.success()
            removeFromLocalState(videoID: videoID)
        } catch {
            errorMessage = "Failed to share video: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachRecordingsViewModel.moveToSharedFolder", showAlert: false)
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
