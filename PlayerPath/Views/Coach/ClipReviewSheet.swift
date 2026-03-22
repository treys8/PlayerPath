//
//  ClipReviewSheet.swift
//  PlayerPath
//
//  Review sheet for a single coach clip in the Needs Review tab.
//  Lets the coach add notes, then share or discard the clip.
//

import SwiftUI

struct ClipReviewSheet: View {
    let video: CoachVideoItem
    let folder: SharedFolder
    var onShared: (() -> Void)?
    var onDiscarded: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var notes: String
    @State private var isPublishing = false
    @State private var isDiscarding = false
    @State private var showingDiscardConfirmation = false
    @State private var errorMessage: String?

    private var folderID: String { folder.id ?? "" }

    init(video: CoachVideoItem, folder: SharedFolder, onShared: (() -> Void)? = nil, onDiscarded: (() -> Void)? = nil) {
        self.video = video
        self.folder = folder
        self.onShared = onShared
        self.onDiscarded = onDiscarded
        self._notes = State(initialValue: video.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Instruction Notes") {
                    TextField("What should the athlete focus on?", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let duration = video.duration, duration > 0 {
                    Section("Info") {
                        LabeledContent("Duration", value: duration.formattedTimestamp)
                        if let createdAt = video.createdAt {
                            LabeledContent("Recorded", value: createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let fileSize = video.fileSize, fileSize > 0 {
                            LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                        }
                    }
                }

                Section {
                    Button {
                        shareClip()
                    } label: {
                        HStack {
                            if isPublishing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Label("Share with Athlete", systemImage: "paperplane.fill")
                        }
                    }
                    .disabled(isPublishing || isDiscarding)

                    Button(role: .destructive) {
                        showingDiscardConfirmation = true
                    } label: {
                        Label("Discard Clip", systemImage: "trash")
                    }
                    .disabled(isPublishing || isDiscarding)
                }
            }
            .navigationTitle("Review Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Discard this clip?", isPresented: $showingDiscardConfirmation) {
                Button("Discard", role: .destructive) { discardClip() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clip will be permanently deleted.")
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Actions

    private func shareClip() {
        let videoID = video.id
        isPublishing = true

        Task {
            do {
                let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                try await FirestoreManager.shared.publishPrivateVideo(
                    videoID: videoID,
                    sharedFolderID: folderID,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )

                await ActivityNotificationService.shared.postNewVideoNotification(
                    folderID: folderID,
                    folderName: folder.name,
                    uploaderID: video.uploadedBy,
                    uploaderName: video.uploadedByName,
                    coachIDs: [folder.ownerAthleteID],
                    videoFileName: video.fileName
                )

                Haptics.success()
                dismiss()
                onShared?()
            } catch {
                errorMessage = "Failed to share clip: \(error.localizedDescription)"
                ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.shareClip", showAlert: false)
                isPublishing = false
            }
        }
    }

    private func discardClip() {
        let videoID = video.id
        isDiscarding = true

        Task {
            do {
                try await FirestoreManager.shared.deleteCoachPrivateVideo(
                    videoID: videoID,
                    sharedFolderID: folderID,
                    fileName: video.fileName
                )
                Haptics.success()
                dismiss()
                onDiscarded?()
            } catch {
                errorMessage = "Failed to discard clip: \(error.localizedDescription)"
                ErrorHandlerService.shared.handle(error, context: "ClipReviewSheet.discardClip", showAlert: false)
                isDiscarding = false
            }
        }
    }
}
