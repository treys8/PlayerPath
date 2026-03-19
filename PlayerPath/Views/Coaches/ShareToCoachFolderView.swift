//
//  ShareToCoachFolderView.swift
//  PlayerPath
//
//  Sheet for sharing an existing VideoClip to a coach shared folder.
//  Presented from VideoPlayerView menu, PracticesView, GamesView, and HighlightsView.
//

import SwiftUI

struct ShareToCoachFolderView: View {
    let clip: VideoClip

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var folderManager = SharedFolderManager.shared

    @State private var selectedFolder: SharedFolder?
    @State private var notes: String = ""
    @State private var isUploading = false
    @State private var errorMessage: String?
    @FocusState private var notesFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if !authManager.hasCoachingAccess {
                    unauthorizedState
                } else if folderManager.isLoading && folderManager.athleteFolders.isEmpty {
                    ProgressView("Loading folders…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if folderManager.athleteFolders.isEmpty {
                    emptyState
                } else {
                    folderPicker
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Share to Coach Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { notesFocused = false }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await share() }
                    } label: {
                        if isUploading {
                            ProgressView()
                        } else {
                            Text("Share")
                        }
                    }
                    .disabled(selectedFolder == nil || isUploading)
                }
            }
            .overlay {
                if isUploading {
                    uploadingOverlay
                }
            }
        }
        .task {
            await loadFolders()
        }
    }

    // MARK: - Sub-views

    private var unauthorizedState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("Pro Required")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Coach sharing is a Pro feature. Upgrade to Pro to share videos with your coaches.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Dismiss") { dismiss() }
                .padding(.top, 8)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "folder.badge.person.crop")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("No Coach Folders")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Create a coach folder in the Coaches tab, invite a coach, then come back to share this video.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var folderPicker: some View {
        Form {
            Section("Select Folder") {
                ForEach(folderManager.athleteFolders) { folder in
                    Button {
                        selectedFolder = folder
                        Haptics.selection()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("\(folder.sharedWithCoachIDs.count) coach\(folder.sharedWithCoachIDs.count == 1 ? "" : "es") · \(folder.videoCount ?? 0) video\(folder.videoCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedFolder?.id == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }

            Section {
                TextField("Add context for your coach…", text: $notes, axis: .vertical)
                    .focused($notesFocused)
                    .lineLimit(3...6)
            } header: {
                Text("Notes (Optional)")
            } footer: {
                if let game = clip.game {
                    Text("Linked to: vs \(game.opponent)")
                } else if clip.practice != nil {
                    Text("Linked to: Practice")
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var uploadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.4)
                Text("Uploading…")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Logic

    private func loadFolders() async {
        guard let athleteUID = authManager.userID else { return }
        try? await SharedFolderManager.shared.loadAthleteFolders(athleteID: athleteUID)
    }

    private func share() async {
        guard let folder = selectedFolder, let folderID = folder.id else { return }
        guard let uploaderUID = authManager.userID else {
            errorMessage = "Not signed in."
            return
        }

        let videoURL = clip.resolvedFileURL
        guard FileManager.default.fileExists(atPath: clip.resolvedFilePath) else {
            errorMessage = "Video file not found locally. Open the video to download it first, then share."
            return
        }

        isUploading = true
        errorMessage = nil

        let uploaderName = authManager.userDisplayName ?? authManager.userEmail ?? "Athlete"
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Determine video type and context from the clip's existing associations
        let videoType: String
        let gameCtx: GameContext?
        let practiceCtx: PracticeContext?

        if let game = clip.game {
            videoType = "game"
            gameCtx = GameContext(
                opponent: game.opponent,
                date: game.date ?? Date(),
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            practiceCtx = nil
        } else if let practice = clip.practice {
            videoType = "practice"
            gameCtx = nil
            practiceCtx = PracticeContext(
                date: practice.date ?? Date(),
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
        } else if clip.isHighlight {
            videoType = "highlight"
            gameCtx = trimmedNotes.isEmpty ? nil : GameContext(opponent: "", date: Date(), notes: trimmedNotes)
            practiceCtx = nil
        } else {
            videoType = "game"
            gameCtx = trimmedNotes.isEmpty ? nil : GameContext(opponent: "", date: Date(), notes: trimmedNotes)
            practiceCtx = nil
        }

        do {
            _ = try await SharedFolderManager.shared.uploadVideo(
                from: videoURL,
                fileName: clip.fileName,
                toFolder: folderID,
                uploadedBy: uploaderUID,
                uploadedByName: uploaderName,
                videoType: videoType,
                gameContext: gameCtx,
                practiceContext: practiceCtx
            )
            isUploading = false
            Haptics.success()
            dismiss()
        } catch {
            isUploading = false
            errorMessage = "Upload failed: \(error.localizedDescription)"
        }
    }
}
