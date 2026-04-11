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
    private var folderManager: SharedFolderManager { .shared }

    @State private var selectedFolder: SharedFolder?
    @State private var notes: String = ""
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
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
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.2.badge.gearshape")
                .font(.system(size: 56))
                .foregroundColor(.brandNavy)

            Text("Share Videos with Your Coach")
                .font(.title2)
                .fontWeight(.bold)

            Text("Get personalized feedback on your game and practice clips.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "message.badge.circle", text: "Timestamped coach feedback on every clip")
                featureRow(icon: "list.clipboard", text: "Drill cards for structured skill reviews")
                featureRow(icon: "folder.badge.person.crop", text: "Organized shared folders per coach")
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                dismiss()
                NotificationCenter.default.post(name: .showSubscriptionPaywall, object: nil)
            } label: {
                Text("View Plans")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.brandNavy)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)

            Button("Restore Purchases") {
                Task { await StoreKitManager.shared.restorePurchases() }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.bottom, 16)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.brandNavy)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
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
                                    .foregroundColor(.brandNavy)
                            }
                        }
                    }
                }
            }

            Section {
                TextField("Add context for your coach…", text: $notes, axis: .vertical)
                    .focused($notesFocused)
                    .lineLimit(3...6)
                    .onChange(of: notes) { _, new in
                        if new.count > CoachNoteLimits.plainNoteCharLimit {
                            notes = String(new.prefix(CoachNoteLimits.plainNoteCharLimit))
                        }
                    }
                HStack {
                    Spacer()
                    Text("\(notes.count)/\(CoachNoteLimits.plainNoteCharLimit)")
                        .font(.caption2)
                        .foregroundColor(notes.count >= CoachNoteLimits.plainNoteCharLimit ? .red : .secondary)
                }
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
                ProgressView(value: uploadProgress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 180)
                Text("Uploading \(Int(uploadProgress * 100))%")
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
        do {
            try await SharedFolderManager.shared.loadAthleteFolders(athleteID: athleteUID)
        } catch {
            ErrorHandlerService.shared.handle(error, context: "ShareToCoachFolder.loadFolders", showAlert: false)
        }
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
        uploadProgress = 0
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
            videoType = "other"
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
                practiceContext: practiceCtx,
                playResult: clip.playResult?.type.displayName,
                pitchSpeed: clip.pitchSpeed,
                pitchType: clip.pitchType,
                seasonName: clip.seasonName ?? clip.season?.name,
                athleteName: clip.athlete?.name,
                isHighlight: clip.isHighlight,
                clipNote: clip.note,
                existingThumbnailPath: clip.thumbnailPath,
                progressHandler: { progress in
                    Task { @MainActor in
                        uploadProgress = progress
                    }
                }
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
