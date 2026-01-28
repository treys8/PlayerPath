//
//  CoachVideoPlayerView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Video player with annotation/notes system for coaches and athletes
//

import SwiftUI
import AVKit
import Combine
import CoreMedia

struct CoachVideoPlayerView: View {
    let folder: SharedFolder
    let video: CoachVideoItem
    
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var viewModel: CoachVideoPlayerViewModel
    @State private var showingAddNote = false
    @State private var selectedTab: VideoTab = .notes
    
    init(folder: SharedFolder, video: CoachVideoItem) {
        self.folder = folder
        self.video = video
        _viewModel = StateObject(wrappedValue: CoachVideoPlayerViewModel(video: video, folder: folder))
    }
    
    enum VideoTab: String, CaseIterable {
        case notes = "Notes"
        case info = "Info"
        
        var icon: String {
            switch self {
            case .notes: return "bubble.left.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Video Player with annotation markers
            if let player = viewModel.player {
                ZStack(alignment: .bottom) {
                    VideoPlayer(player: player)
                        .frame(height: 250)
                        .onAppear {
                            player.play()
                            viewModel.startTimeObserver()
                        }
                        .onDisappear {
                            player.pause()
                            viewModel.stopTimeObserver()
                        }

                    // Annotation markers overlay
                    if !viewModel.annotations.isEmpty, let duration = viewModel.videoDuration, duration > 0 {
                        GeometryReader { geometry in
                            HStack(spacing: 0) {
                                ForEach(viewModel.annotations) { annotation in
                                    Spacer()
                                        .frame(width: (CGFloat(annotation.timestamp) / CGFloat(duration)) * geometry.size.width)
                                    VStack {
                                        Spacer()
                                        Rectangle()
                                            .fill(annotation.isCoachComment ? Color.green : Color.blue)
                                            .frame(width: 3, height: 20)
                                            .shadow(color: .black.opacity(0.5), radius: 2)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .allowsHitTesting(false)
                    }
                }
            } else if viewModel.isLoading {
                ZStack {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 250)
                    
                    ProgressView("Loading video...")
                        .tint(.white)
                }
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 250)
                    
                    Text("Failed to load video")
                        .foregroundColor(.white)
                }
            }
            
            // Tab selector
            Picker("View", selection: $selectedTab) {
                ForEach(VideoTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content based on selected tab
            Group {
                switch selectedTab {
                case .notes:
                    NotesTabView(
                        notes: viewModel.annotations,
                        isLoading: viewModel.isLoadingAnnotations,
                        onAddNote: {
                            showingAddNote = true
                        },
                        onDeleteNote: { note in
                            Task {
                                await viewModel.deleteAnnotation(note)
                            }
                        },
                        onSeekToTimestamp: { timestamp in
                            viewModel.seekToTimestamp(timestamp)
                        },
                        canComment: canComment
                    )
                case .info:
                    VideoInfoTabView(video: video)
                }
            }
        }
        .navigationTitle(video.fileName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddNote) {
            AddNoteView(
                currentTime: viewModel.currentPlaybackTime,
                onSave: { noteText, timestamp in
                    Task {
                        await addNote(text: noteText, timestamp: timestamp)
                    }
                }
            )
        }
        .task {
            await viewModel.loadVideo()
            await viewModel.loadAnnotations()
        }
    }
    
    private var canComment: Bool {
        guard let coachID = authManager.userID else { return false }
        return folder.getPermissions(for: coachID)?.canComment ?? false
    }
    
    private func addNote(text: String, timestamp: Double) async {
        guard let userID = authManager.userID,
              let userName = authManager.userDisplayName ?? authManager.userEmail else {
            return
        }
        
        let isCoach = authManager.userRole == .coach
        
        await viewModel.addAnnotation(
            text: text,
            timestamp: timestamp,
            userID: userID,
            userName: userName,
            isCoachComment: isCoach
        )
    }
}

// MARK: - Notes Tab View

struct NotesTabView: View {
    let notes: [VideoAnnotation]
    let isLoading: Bool
    let onAddNote: () -> Void
    let onDeleteNote: (VideoAnnotation) -> Void
    let onSeekToTimestamp: (Double) -> Void
    let canComment: Bool

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Add note button
            if canComment {
                Button(action: onAddNote) {
                    Label("Add Note", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                }
            }
            
            Divider()
            
            // Notes list
            if isLoading {
                ProgressView("Loading notes...")
                    .frame(maxHeight: .infinity)
            } else if notes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "note.text")
                        .font(.system(size: 50))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("No notes yet")
                        .font(.headline)
                    
                    Text("Add notes and feedback at specific timestamps in the video.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(notes) { note in
                            NoteCardView(
                                note: note,
                                canDelete: note.userID == authManager.userID,
                                onDelete: {
                                    onDeleteNote(note)
                                },
                                onSeek: {
                                    onSeekToTimestamp(note.timestamp)
                                    Haptics.light()
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - Note Card View

struct NoteCardView: View {
    let note: VideoAnnotation
    let canDelete: Bool
    let onDelete: () -> Void
    let onSeek: () -> Void

    @State private var showingDeleteAlert = false

    var body: some View {
        Button(action: onSeek) {
            VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: note.isCoachComment ? "person.fill.checkmark" : "person.fill")
                    .font(.caption)
                    .foregroundColor(note.isCoachComment ? .green : .blue)
                
                Text(note.userName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(note.isCoachComment ? .green : .blue)
                
                if note.isCoachComment {
                    Text("COACH")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
                
                Spacer()
                
                if canDelete {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Timestamp marker
            HStack {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                Text(formatTimestamp(note.timestamp))
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundColor(.secondary)
            
            // Note text
            Text(note.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            
            // Timestamp
            if let createdAt = note.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .alert("Delete Note", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this note?")
        }
    }
    
    private func formatTimestamp(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Video Info Tab View

struct VideoInfoTabView: View {
    let video: CoachVideoItem
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoRow(label: "File Name", value: video.fileName)
                InfoRow(label: "Uploaded By", value: video.uploadedByName)
                
                if let date = video.createdAt {
                    InfoRow(label: "Upload Date", value: date.formatted(date: .long, time: .shortened))
                }
                
                if let context = video.contextLabel {
                    InfoRow(label: "Context", value: context)
                }
                
                if let opponent = video.gameOpponent {
                    InfoRow(label: "Opponent", value: opponent)
                }
                
                if let duration = video.duration {
                    InfoRow(label: "Duration", value: formatDuration(duration))
                }
                
                if let fileSize = video.fileSize {
                    InfoRow(label: "File Size", value: formatFileSize(fileSize))
                }
                
                if video.isHighlight {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text("Highlight Video")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - Add Note View

struct AddNoteView: View {
    let currentTime: Double
    let onSave: (String, Double) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""
    @State private var timestamp: Double
    
    init(currentTime: Double, onSave: @escaping (String, Double) -> Void) {
        self.currentTime = currentTime
        self.onSave = onSave
        _timestamp = State(initialValue: currentTime)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Timestamp")
                        Spacer()
                        Text(formatTimestamp(timestamp))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Note") {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 150)
                }
                
                Section {
                    Text("Add feedback, coaching tips, or observations at this point in the video.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(noteText, timestamp)
                        dismiss()
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func formatTimestamp(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - View Model

@MainActor
class CoachVideoPlayerViewModel: ObservableObject {
    let video: CoachVideoItem
    let folder: SharedFolder
    
    @Published var player: AVPlayer?
    @Published var isLoading = false
    @Published var annotations: [VideoAnnotation] = []
    @Published var isLoadingAnnotations = false
    @Published var errorMessage: String?
    
    var currentPlaybackTime: Double {
        player?.currentTime().seconds ?? 0.0
    }
    
    init(video: CoachVideoItem, folder: SharedFolder) {
        self.video = video
        self.folder = folder
    }
    
    func loadVideo() async {
        isLoading = true
        
        // Load video from Firebase Storage URL
        if let url = URL(string: video.firebaseStorageURL) {
            player = AVPlayer(url: url)
        }
        
        isLoading = false
    }
    
    func loadAnnotations() async {
        isLoadingAnnotations = true
        
        do {
            guard let videoID = video.id as String? else {
                isLoadingAnnotations = false
                return
            }
            
            annotations = try await FirestoreManager.shared.fetchAnnotations(forVideo: videoID)
                .sorted { ($0.timestamp) < ($1.timestamp) }
            
        } catch {
            errorMessage = "Failed to load notes: \(error.localizedDescription)"
            print("❌ Failed to load annotations: \(error)")
        }
        
        isLoadingAnnotations = false
    }
    
    func addAnnotation(
        text: String,
        timestamp: Double,
        userID: String,
        userName: String,
        isCoachComment: Bool
    ) async {
        do {
            guard let videoID = video.id as String? else { return }
            
            let annotation = try await FirestoreManager.shared.createAnnotation(
                videoID: videoID,
                text: text,
                timestamp: timestamp,
                userID: userID,
                userName: userName,
                isCoachComment: isCoachComment
            )
            
            annotations.append(annotation)
            annotations.sort { $0.timestamp < $1.timestamp }
            
            HapticManager.shared.success()
            
        } catch {
            errorMessage = "Failed to add note: \(error.localizedDescription)"
            print("❌ Failed to add annotation: \(error)")
            HapticManager.shared.error()
        }
    }
    
    func deleteAnnotation(_ annotation: VideoAnnotation) async {
        do {
            guard let videoID = video.id as String?,
                  let annotationID = annotation.id else { return }

            try await FirestoreManager.shared.deleteAnnotation(videoID: videoID, annotationID: annotationID)

            annotations.removeAll { $0.id == annotationID }

            HapticManager.shared.success()

        } catch {
            errorMessage = "Failed to delete note: \(error.localizedDescription)"
            print("❌ Failed to delete annotation: \(error)")
            HapticManager.shared.error()
        }
    }

    // MARK: - Video Playback Control

    @Published var videoDuration: Double?
    private var timeObserver: Any?

    func startTimeObserver() {
        guard let player = player else { return }

        // Observe duration
        if let currentItem = player.currentItem {
            Task {
                do {
                    let duration = try await currentItem.asset.load(.duration)
                    await MainActor.run {
                        self.videoDuration = duration.seconds
                    }
                } catch {
                    print("Failed to load video duration: \(error)")
                }
            }
        }

        // Observe current time (for seeking functionality)
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            // Update UI if needed
        }
    }

    func stopTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    func seekToTimestamp(_ timestamp: Double) {
        let time = CMTime(seconds: timestamp, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CoachVideoPlayerView(
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
            video: CoachVideoItem(
                from: FirestoreVideoMetadata(
                    id: "video123",
                    fileName: "practice_2024-11-21.mov",
                    firebaseStorageURL: "https://example.com/video.mov",
                    thumbnail: nil,
                    uploadedBy: "coach456",
                    uploadedByName: "Coach Smith",
                    sharedFolderID: "folder123",
                    createdAt: Date(),
                    fileSize: 1024000,
                    duration: 120.0,
                    isHighlight: false,
                    uploadedByType: .coach,
                    isOrphaned: false,
                    orphanedAt: nil,
                    videoType: "practice",
                    gameOpponent: nil,
                    gameDate: nil,
                    practiceDate: Date(),
                    notes: nil
                )
            )
        )
    }
    .environmentObject(ComprehensiveAuthManager())
}
