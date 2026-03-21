//
//  CoachQuickRecordFlow.swift
//  PlayerPath
//
//  "Record first, pick athlete after" flow for coaches.
//  Opens camera immediately, then presents a folder picker
//  to save the recording.
//

import SwiftUI
import FirebaseAuth
import Combine

/// Full-screen flow: Camera → Save Recording sheet
struct CoachQuickRecordFlow: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var folderManager = SharedFolderManager.shared

    @State private var recordedVideoURL: URL?
    @State private var showingSaveSheet = false

    var body: some View {
        ModernCameraView(
            onVideoRecorded: { url in
                recordedVideoURL = url
                showingSaveSheet = true
            },
            onCancel: {
                dismiss()
            }
        )
        .sheet(isPresented: $showingSaveSheet, onDismiss: {
            // If user dismisses without saving, clean up and close
            if let url = recordedVideoURL {
                try? FileManager.default.removeItem(at: url)
                recordedVideoURL = nil
            }
            dismiss()
        }) {
            if let videoURL = recordedVideoURL {
                SaveRecordingSheet(videoURL: videoURL, onSaved: {
                    recordedVideoURL = nil
                    dismiss()
                })
            }
        }
    }
}

// MARK: - Save Recording Sheet

/// After recording, coach picks which athlete/folder to save to
struct SaveRecordingSheet: View {
    let videoURL: URL
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var folderManager = SharedFolderManager.shared

    @State private var selectedFolder: SharedFolder?
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveMode: SaveMode = .staging

    enum SaveMode {
        case staging   // Save to My Recordings (private)
        case shared    // Save & Share (directly to shared folder)
    }

    /// Folders the coach has upload permission for
    private var uploadableFolders: [SharedFolder] {
        guard let coachID = authManager.userID else { return [] }
        return folderManager.coachFolders.filter { folder in
            folder.getPermissions(for: coachID)?.canUpload == true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if uploadableFolders.isEmpty {
                    noFoldersView
                } else {
                    Form {
                        // Folder picker
                        Section("Select Athlete Folder") {
                            ForEach(uploadableFolders) { folder in
                                Button {
                                    selectedFolder = folder
                                    Haptics.light()
                                } label: {
                                    HStack {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(.green)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(folder.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.primary)
                                            if let athleteName = folder.ownerAthleteName {
                                                Text(athleteName)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if selectedFolder?.id == folder.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                            }
                        }

                        // Notes
                        Section("Notes (Optional)") {
                            TextField("Add notes about this recording...", text: $notes, axis: .vertical)
                                .lineLimit(3...5)
                        }

                        // Save options
                        if selectedFolder != nil {
                            Section {
                                Button {
                                    saveMode = .staging
                                    save()
                                } label: {
                                    HStack {
                                        Image(systemName: "tray.and.arrow.down")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Save to My Recordings")
                                                .fontWeight(.medium)
                                            Text("Review before sharing with athlete")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .disabled(isSaving)

                                Button {
                                    saveMode = .shared
                                    save()
                                } label: {
                                    HStack {
                                        Image(systemName: "paperplane.fill")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Save & Share Now")
                                                .fontWeight(.medium)
                                            Text("Athlete can see it immediately")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .disabled(isSaving)
                            }
                        }
                    }
                }

                // Error
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding()
                }

                // Loading overlay
                if isSaving {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Saving recording...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Save Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    // MARK: - No Folders View

    private var noFoldersView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("No Folders Available")
                .font(.title3)
                .fontWeight(.semibold)
            Text("You need upload permission on at least one shared folder to save recordings.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Save Action

    private func save() {
        guard let folder = selectedFolder,
              let folderID = folder.id,
              let coachID = authManager.userID else { return }

        let coachName = Auth.auth().currentUser?.displayName
            ?? Auth.auth().currentUser?.email
            ?? "Coach"

        isSaving = true
        errorMessage = nil

        Task {
            do {
                let dateStr = Date().formatted(.iso8601.year().month().day())
                let fileName = "practice_\(dateStr)_\(UUID().uuidString.prefix(8)).mov"

                let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0

                // Upload to Storage (always under shared_folders path)
                let storageURL = try await VideoCloudManager.shared.uploadVideo(
                    localURL: videoURL,
                    fileName: fileName,
                    folderID: folderID,
                    progressHandler: { _ in }
                )

                // Process video: extract duration + generate/upload thumbnail
                let processed = await CoachVideoProcessingService.shared.process(
                    videoURL: videoURL,
                    fileName: fileName,
                    folderID: folderID
                )

                if saveMode == .staging {
                    // Save to private staging folder
                    let privateFolder = try await FirestoreManager.shared.getOrCreatePrivateFolder(
                        coachID: coachID,
                        athleteID: folder.ownerAthleteID,
                        sharedFolderID: folderID
                    )
                    _ = try await FirestoreManager.shared.createPrivateVideo(
                        privateFolderID: privateFolder.id ?? "",
                        fileName: fileName,
                        storageURL: storageURL,
                        uploadedBy: coachID,
                        uploadedByName: coachName,
                        fileSize: fileSize,
                        duration: processed.duration,
                        thumbnailURL: processed.thumbnailURL,
                        notes: notes.isEmpty ? nil : notes
                    )
                } else {
                    // Save directly to shared folder
                    _ = try await FirestoreManager.shared.uploadVideoMetadata(
                        fileName: fileName,
                        storageURL: storageURL,
                        thumbnail: processed.thumbnailURL.map { ThumbnailMetadata(standardURL: $0) },
                        folderID: folderID,
                        uploadedBy: coachID,
                        uploadedByName: coachName,
                        fileSize: fileSize,
                        duration: processed.duration,
                        videoType: "practice",
                        practiceContext: notes.isEmpty ? nil : PracticeContext(date: Date(), notes: notes),
                        uploadedByType: .coach
                    )
                }

                // Clean up local file
                try? FileManager.default.removeItem(at: videoURL)

                await MainActor.run {
                    Haptics.success()
                    onSaved()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                    ErrorHandlerService.shared.handle(error, context: "CoachQuickRecordFlow.saveRecording", showAlert: false)
                }
            }
        }
    }
}
