//
//  CoachVideoUploadView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Video upload interface for coaches to add videos to athlete folders
//

import SwiftUI
import PhotosUI
import AVFoundation
import AVKit


struct CoachVideoUploadView: View {
    let folder: SharedFolder

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var viewModel: CoachVideoUploadViewModel
    @FocusState private var focusedField: UploadField?
    enum UploadField: Hashable { case opponent, notes }

    init(folder: SharedFolder, defaultContext: VideoContext = .instruction) {
        self.folder = folder
        _viewModel = State(initialValue: CoachVideoUploadViewModel(folder: folder, defaultContext: defaultContext))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Video Source") {
                    Button(action: {
                        viewModel.showingPhotoPicker = true
                    }) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                    
                    Button(action: {
                        viewModel.showingCamera = true
                    }) {
                        Label("Record Video", systemImage: "video")
                    }
                }
                
                if viewModel.selectedVideoURL != nil {
                    Section("Selected Video") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.brandNavy)
                            Text("Video selected")
                            Spacer()
                            Button("Change") {
                                viewModel.clearSelection()
                            }
                            .font(.caption)
                        }
                    }
                    
                    Section("Video Context") {
                        Picker("Upload to", selection: $viewModel.videoContext) {
                            Text("Game").tag(VideoContext.game)
                            Text("Instruction").tag(VideoContext.instruction)
                        }
                        .pickerStyle(.segmented)
                        
                        if viewModel.videoContext == .game {
                            TextField("Opponent", text: $viewModel.gameOpponent)
                                .focused($focusedField, equals: .opponent)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .notes }
                                .textInputAutocapitalization(.words)

                            DatePicker("Game Date", selection: $viewModel.contextDate, displayedComponents: .date)
                        } else {
                            DatePicker("Instruction Date", selection: $viewModel.contextDate, displayedComponents: .date)
                        }

                        TextField("Notes (optional)", text: $viewModel.notes, axis: .vertical)
                            .focused($focusedField, equals: .notes)
                            .lineLimit(3...6)
                    }
                    
                    Section {
                        Toggle("Mark as Highlight", isOn: $viewModel.isHighlight)
                    }
                    
                    if viewModel.isUploading {
                        Section {
                            VStack(spacing: 12) {
                                ProgressView(value: viewModel.uploadProgress)
                                    .progressViewStyle(.linear)
                                
                                Text("Uploading: \(Int(viewModel.uploadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if let errorMessage = viewModel.errorMessage {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                                    .font(.caption)

                                Button {
                                    Task { await uploadVideo() }
                                } label: {
                                    Label("Try Again", systemImage: "arrow.clockwise")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.brandNavy)
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Upload Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isUploading)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
                        guard !viewModel.isUploading else { return }
                        Task {
                            await uploadVideo()
                        }
                    }
                    .disabled(!viewModel.canUpload)
                }
            }
            .photosPicker(
                isPresented: $viewModel.showingPhotoPicker,
                selection: $viewModel.selectedPhotoItem,
                matching: .videos
            )
            .fullScreenCover(isPresented: $viewModel.showingCamera) {
                ModernCameraView(
                    onVideoRecorded: { url in
                        viewModel.selectedVideoURL = url
                        viewModel.showingCamera = false
                    },
                    onCancel: {
                        viewModel.showingCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .overlay {
                if viewModel.uploadComplete {
                    ZStack {
                        Color(.systemBackground).ignoresSafeArea()
                        VStack(spacing: 20) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 72))
                                .foregroundColor(.brandNavy)
                            Text("Upload Complete!")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Video added to \(folder.name).")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeIn(duration: 0.2), value: viewModel.uploadComplete)
            .onChange(of: viewModel.selectedPhotoItem) { _, newItem in
                Task {
                    await viewModel.loadVideo(from: newItem)
                }
            }
            .onChange(of: viewModel.uploadComplete) { _, complete in
                if complete {
                    Task {
                        try? await Task.sleep(for: .milliseconds(800))
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func uploadVideo() async {
        guard let userID = authManager.userID,
              let userName = authManager.userDisplayName ?? authManager.userEmail else {
            viewModel.errorMessage = "Not authenticated"
            return
        }
        
        await viewModel.uploadVideo(
            uploaderID: userID,
            uploaderName: userName
        )
    }
}

// MARK: - Video Context

enum VideoContext {
    case game
    case instruction
}

// MARK: - View Model

@MainActor
@Observable
class CoachVideoUploadViewModel {
    let folder: SharedFolder

    var showingPhotoPicker = false
    var showingCamera = false
    var selectedPhotoItem: PhotosPickerItem?
    var selectedVideoURL: URL?

    var videoContext: VideoContext = .instruction
    var gameOpponent: String = ""
    var contextDate: Date = Date()
    var notes: String = ""
    var isHighlight: Bool = false

    var isUploading = false
    var uploadProgress: Double = 0.0
    var uploadComplete = false
    var errorMessage: String?
    
    private var pickerTempURL: URL?

    init(folder: SharedFolder, defaultContext: VideoContext = .instruction) {
        self.folder = folder
        self.videoContext = defaultContext
    }

    var canUpload: Bool {
        guard selectedVideoURL != nil, !isUploading else { return false }
        if videoContext == .game {
            return !gameOpponent.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    func clearSelection() {
        if let url = pickerTempURL {
            Task.detached { try? FileManager.default.removeItem(at: url) }
            pickerTempURL = nil
        }
        selectedVideoURL = nil
        selectedPhotoItem = nil
    }
    
    func loadVideo(from item: PhotosPickerItem?) async {
        guard let item = item else { return }

        // Clean up any previous picker temp file before loading a new one
        if let existing = pickerTempURL {
            try? FileManager.default.removeItem(at: existing)
            pickerTempURL = nil
        }

        do {
            guard let movie = try await item.loadTransferable(type: VideoPickerTransferable.self) else {
                errorMessage = "Failed to load video"
                return
            }
            pickerTempURL = movie.url
            selectedVideoURL = movie.url
        } catch {
            errorMessage = "Failed to load video: \(error.localizedDescription)"
        }
    }
    
    func uploadVideo(uploaderID: String, uploaderName: String) async {
        guard let videoURL = selectedVideoURL,
              let folderID = folder.id else {
            errorMessage = "Missing video or folder information"
            return
        }

        isUploading = true
        uploadComplete = false
        errorMessage = nil
        uploadProgress = 0.0

        // Pre-flight: verify uploader still has folder access and upload permission
        do {
            let latestFolder = try await FirestoreManager.shared.fetchSharedFolder(folderID: folderID)
            guard let latestFolder else {
                errorMessage = "This folder no longer exists."
                isUploading = false
                return
            }
            let hasUploadPerm = latestFolder.getPermissions(for: uploaderID)?.canUpload == true
                || latestFolder.ownerAthleteID == uploaderID
            if !hasUploadPerm {
                errorMessage = "You don't have upload permission for this folder."
                isUploading = false
                return
            }
        } catch {
            errorMessage = "Unable to verify folder access. Please check your connection and try again."
            isUploading = false
            return
        }

        do {
            // Generate file name
            let fileName = generateFileName()
            
            // Step 1: Generate thumbnail (10% of progress)
            uploadProgress = 0.05
            let thumbnailResult = await VideoFileManager.generateThumbnail(from: videoURL)
            
            var thumbnailURL: String?
            
            if case .success(let localThumbnailPath) = thumbnailResult {
                // Step 2: Upload thumbnail (20% of progress)
                uploadProgress = 0.15
                do {
                    thumbnailURL = try await VideoCloudManager.shared.uploadThumbnail(
                        thumbnailURL: URL(fileURLWithPath: localThumbnailPath),
                        videoFileName: fileName,
                        folderID: folderID
                    )
                    
                    // Clean up local thumbnail
                    VideoFileManager.cleanup(url: URL(fileURLWithPath: localThumbnailPath))
                } catch {
                    // Continue even if thumbnail fails — video upload proceeds without thumbnail
                    ErrorHandlerService.shared.handle(error, context: "CoachVideoUpload.generateThumbnail", showAlert: false)
                }
            } else {
                ErrorHandlerService.shared.handle(
                    NSError(domain: "CoachVideoUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Thumbnail generation failed"]),
                    context: "CoachVideoUpload.thumbnailGeneration",
                    showAlert: false
                )
            }

            uploadProgress = 0.2
            
            // Step 3: Upload video (20% - 100% of progress)
            let storageURL = try await VideoCloudManager.shared.uploadVideo(
                localURL: videoURL,
                fileName: fileName,
                folderID: folderID,
                progressHandler: { videoProgress in
                    Task { @MainActor in
                        // Map video progress from 20% to 100%
                        self.uploadProgress = 0.2 + (videoProgress * 0.8)
                    }
                }
            )
            
            // Extract file size and duration before creating metadata
            let fileSize: Int64
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: videoURL.path)
                fileSize = attrs[.size] as? Int64 ?? 0
            } catch {
                fileSize = 0
            }

            let duration: Double?
            do {
                let asset = AVURLAsset(url: videoURL)
                let cmDuration = try await asset.load(.duration)
                duration = cmDuration.seconds.isFinite ? cmDuration.seconds : nil
            } catch {
                duration = nil
            }

            // Step 4: Create metadata in Firestore
            let metadata = createMetadata(
                fileName: fileName,
                storageURL: storageURL,
                thumbnailURL: thumbnailURL,
                uploaderID: uploaderID,
                uploaderName: uploaderName,
                fileSize: fileSize,
                duration: duration
            )
            
            _ = try await FirestoreManager.shared.createVideoMetadata(
                folderID: folderID,
                metadata: metadata
            )

            // Notify the athlete (folder owner) that the coach added a video
            // Note: coachIDs param is used as generic recipientIDs by the notification service
            await ActivityNotificationService.shared.postNewVideoNotification(
                folderID: folderID,
                folderName: folder.name,
                uploaderID: uploaderID,
                uploaderName: uploaderName,
                coachIDs: [folder.ownerAthleteID],
                videoFileName: fileName
            )

            uploadComplete = true
            Haptics.success()

        } catch {
            errorMessage = "Upload failed: \(error.localizedDescription)"
            ErrorHandlerService.shared.handle(error, context: "CoachVideoUploadView.uploadVideo", showAlert: false)
        }

        // Clean up picker temp file regardless of outcome
        if let url = pickerTempURL {
            try? FileManager.default.removeItem(at: url)
            pickerTempURL = nil
        }

        isUploading = false
    }
    
    private func generateFileName() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let timestamp = formatter.string(from: Date())
        let uid = UUID().uuidString.prefix(8)

        switch videoContext {
        case .game:
            let raw = gameOpponent.trimmingCharacters(in: .whitespaces).isEmpty ? "Unknown" : gameOpponent
            let sanitized = raw
                .components(separatedBy: CharacterSet(charactersIn: "/\\#?% "))
                .joined(separator: "_")
            return "game_\(sanitized)_\(timestamp)_\(uid).mov"
        case .instruction:
            return "instruction_\(timestamp)_\(uid).mov"
        }
    }
    
    private func createMetadata(
        fileName: String,
        storageURL: String,
        thumbnailURL: String?,
        uploaderID: String,
        uploaderName: String,
        fileSize: Int64 = 0,
        duration: Double? = nil
    ) -> [String: Any] {
        var metadata: [String: Any] = [
            "fileName": fileName,
            "firebaseStorageURL": storageURL,
            "uploadedBy": uploaderID,
            "uploadedByName": uploaderName,
            "uploadedByType": "coach",
            "sharedFolderID": folder.id ?? "",
            "isHighlight": isHighlight,
            "createdAt": Date()
        ]

        if fileSize > 0 {
            metadata["fileSize"] = fileSize
        }
        if let duration {
            metadata["duration"] = duration
        }
        
        // Add thumbnail URL if available
        if let thumbnailURL = thumbnailURL {
            metadata["thumbnailURL"] = thumbnailURL
        }
        
        // Add context-specific metadata
        switch videoContext {
        case .game:
            metadata["gameOpponent"] = gameOpponent
            metadata["gameDate"] = contextDate
            metadata["videoType"] = "game"
        case .instruction:
            metadata["practiceDate"] = contextDate
            metadata["videoType"] = "instruction"
        }
        
        if !notes.isEmpty {
            metadata["notes"] = notes
        }
        
        return metadata
    }
}

// MARK: - Video Picker Transferable

struct VideoPickerTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = URL.documentsDirectory.appending(path: "imported_\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

// MARK: - Preview

#Preview {
    CoachVideoUploadView(
        folder: SharedFolder(
            id: "preview",
            name: "Test Folder",
            ownerAthleteID: "athlete123",
            ownerAthleteName: "Test Athlete",
            sharedWithCoachIDs: ["coach456"],
            permissions: [:],
            createdAt: Date(),
            updatedAt: Date(),
            videoCount: 0
        ),
        defaultContext: .instruction
    )
    .environmentObject(ComprehensiveAuthManager())
}
