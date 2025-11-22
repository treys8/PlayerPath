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

struct CoachVideoUploadView: View {
    let folder: SharedFolder
    let selectedTab: CoachFolderDetailView.FolderTab
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var viewModel: CoachVideoUploadViewModel
    
    init(folder: SharedFolder, selectedTab: CoachFolderDetailView.FolderTab) {
        self.folder = folder
        self.selectedTab = selectedTab
        _viewModel = StateObject(wrappedValue: CoachVideoUploadViewModel(folder: folder))
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
                        Label("Record Video", systemImage: "video.fill")
                    }
                }
                
                if viewModel.selectedVideoURL != nil {
                    Section("Selected Video") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Video selected")
                            Spacer()
                            Button("Change") {
                                viewModel.selectedVideoURL = nil
                            }
                            .font(.caption)
                        }
                    }
                    
                    Section("Video Context") {
                        Picker("Upload to", selection: $viewModel.videoContext) {
                            Text("Game").tag(VideoContext.game)
                            Text("Practice").tag(VideoContext.practice)
                        }
                        .pickerStyle(.segmented)
                        
                        if viewModel.videoContext == .game {
                            TextField("Opponent", text: $viewModel.gameOpponent)
                                .textInputAutocapitalization(.words)
                            
                            DatePicker("Game Date", selection: $viewModel.contextDate, displayedComponents: .date)
                        } else {
                            DatePicker("Practice Date", selection: $viewModel.contextDate, displayedComponents: .date)
                        }
                        
                        TextField("Notes (optional)", text: $viewModel.notes, axis: .vertical)
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
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Upload Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isUploading)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
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
                VideoRecordingView(onVideoRecorded: { url in
                    viewModel.selectedVideoURL = url
                })
            }
            .onChange(of: viewModel.selectedPhotoItem) { _, newItem in
                Task {
                    await viewModel.loadVideo(from: newItem)
                }
            }
            .onChange(of: viewModel.uploadComplete) { _, complete in
                if complete {
                    dismiss()
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
    case practice
}

// MARK: - View Model

@MainActor
class CoachVideoUploadViewModel: ObservableObject {
    let folder: SharedFolder
    
    @Published var showingPhotoPicker = false
    @Published var showingCamera = false
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var selectedVideoURL: URL?
    
    @Published var videoContext: VideoContext = .practice
    @Published var gameOpponent: String = ""
    @Published var contextDate: Date = Date()
    @Published var notes: String = ""
    @Published var isHighlight: Bool = false
    
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    @Published var uploadComplete = false
    @Published var errorMessage: String?
    
    init(folder: SharedFolder) {
        self.folder = folder
    }
    
    var canUpload: Bool {
        selectedVideoURL != nil && !isUploading
    }
    
    func loadVideo(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        do {
            guard let movie = try await item.loadTransferable(type: VideoPickerTransferable.self) else {
                errorMessage = "Failed to load video"
                return
            }
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
        errorMessage = nil
        uploadProgress = 0.0
        
        do {
            // Generate file name
            let fileName = generateFileName()
            
            // Upload to Firebase Storage
            let storageURL = try await VideoCloudManager.shared.uploadVideo(
                localURL: videoURL,
                fileName: fileName,
                folderID: folderID,
                progressHandler: { progress in
                    Task { @MainActor in
                        self.uploadProgress = progress
                    }
                }
            )
            
            // Create metadata in Firestore
            let metadata = createMetadata(
                fileName: fileName,
                storageURL: storageURL,
                uploaderID: uploaderID,
                uploaderName: uploaderName
            )
            
            try await FirestoreManager.shared.createVideoMetadata(
                folderID: folderID,
                metadata: metadata
            )
            
            uploadComplete = true
            HapticManager.shared.success()
            
        } catch {
            errorMessage = "Upload failed: \(error.localizedDescription)"
            print("❌ Video upload error: \(error)")
            HapticManager.shared.error()
        }
        
        isUploading = false
    }
    
    private func generateFileName() -> String {
        let timestamp = Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")
        
        switch videoContext {
        case .game:
            let opponent = gameOpponent.isEmpty ? "Unknown" : gameOpponent
            return "game_\(opponent)_\(timestamp).mov"
        case .practice:
            return "practice_\(timestamp).mov"
        }
    }
    
    private func createMetadata(
        fileName: String,
        storageURL: String,
        uploaderID: String,
        uploaderName: String
    ) -> [String: Any] {
        var metadata: [String: Any] = [
            "fileName": fileName,
            "firebaseStorageURL": storageURL,
            "uploadedBy": uploaderID,
            "uploadedByName": uploaderName,
            "sharedFolderID": folder.id ?? "",
            "isHighlight": isHighlight,
            "createdAt": Date()
        ]
        
        // Add context-specific metadata
        switch videoContext {
        case .game:
            metadata["gameOpponent"] = gameOpponent
            metadata["gameDate"] = contextDate
            metadata["videoType"] = "game"
        case .practice:
            metadata["practiceDate"] = contextDate
            metadata["videoType"] = "practice"
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

// MARK: - Simple Video Recording View

struct VideoRecordingView: View {
    let onVideoRecorded: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            Text("Camera Recording")
                .font(.headline)
                .padding()
            
            Spacer()
            
            Text("Camera interface would go here")
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Close") {
                dismiss()
            }
            .padding()
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
            sharedWithCoachIDs: ["coach456"],
            permissions: [:],
            createdAt: Date(),
            updatedAt: Date(),
            videoCount: 0
        ),
        selectedTab: .practices
    )
    .environmentObject(ComprehensiveAuthManager())
}
