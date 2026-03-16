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
    @State private var showingSpeedPicker = false
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(\.scenePhase) private var scenePhase
    private var isLandscape: Bool { vSizeClass == .compact }
    
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
        Group {
            if isLandscape {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .navigationTitle(video.fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSpeedPicker = true
                } label: {
                    Text(viewModel.playbackRate == 1.0
                         ? "1x"
                         : viewModel.playbackRate < 1.0
                             ? String(format: "%.2gx", viewModel.playbackRate)
                             : String(format: "%.4gx", viewModel.playbackRate))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Playback speed: \(viewModel.playbackRate)x")
            }
        }
        .confirmationDialog("Playback Speed", isPresented: $showingSpeedPicker) {
            ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button(rate == 1.0 ? "1x (Normal)" : "\(String(format: "%gx", rate))") {
                    viewModel.setPlaybackRate(rate)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
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
            if viewModel.annotations.isEmpty {
                await viewModel.loadAnnotations()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase != .active {
                viewModel.shouldResumeOnActive = (viewModel.player?.rate ?? 0) > 0
                viewModel.player?.pause()
            } else if newPhase == .active, oldPhase != .active {
                if viewModel.shouldResumeOnActive {
                    viewModel.player?.play()
                }
                viewModel.shouldResumeOnActive = false
            }
        }
    }
    
    // MARK: - Layout Variants

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            playerContent
                .frame(height: 250)
            annotationPanel
        }
    }

    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            playerContent
            Divider()
            annotationPanel
                .frame(width: 320)
        }
    }

    @ViewBuilder
    private var playerContent: some View {
        if let player = viewModel.player, viewModel.isPlayerReady {
            ZStack(alignment: .bottom) {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                        viewModel.startTimeObserver()
                    }
                    .onDisappear {
                        player.pause()
                        viewModel.stopTimeObserver()
                    }

                // Annotation markers overlay
                if !viewModel.annotations.isEmpty,
                   let duration = viewModel.videoDuration, duration > 0 {
                    GeometryReader { geometry in
                        ZStack(alignment: .bottomLeading) {
                            ForEach(viewModel.annotations) { annotation in
                                Rectangle()
                                    .fill(annotation.isCoachComment ? Color.green : Color.blue)
                                    .frame(width: 3, height: 20)
                                    .shadow(color: .black.opacity(0.5), radius: 2)
                                    .offset(x: (CGFloat(annotation.timestamp) / CGFloat(duration)) * geometry.size.width)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                    .allowsHitTesting(false)
                }
            }
        } else if viewModel.isLoading {
            ZStack {
                Color.black
                ProgressView("Loading video...")
                    .tint(.white)
            }
        } else if viewModel.errorMessage != nil {
            ZStack {
                Color(white: 0.3)
                Text("Failed to load video")
                    .foregroundColor(.white)
            }
        } else {
            ZStack {
                Color.black
                ProgressView("Buffering...")
                    .tint(.white)
            }
        }
    }

    private var annotationPanel: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                ForEach(VideoTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                switch selectedTab {
                case .notes:
                    NotesTabView(
                        notes: viewModel.annotations,
                        isLoading: viewModel.isLoadingAnnotations,
                        errorMessage: viewModel.errorMessage,
                        onAddNote: { showingAddNote = true },
                        onDeleteNote: { note in
                            Task { await viewModel.deleteAnnotation(note) }
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
    }

    private var canComment: Bool {
        guard let userID = authManager.userID else { return false }
        if userID == folder.ownerAthleteID { return true }
        return folder.getPermissions(for: userID)?.canComment ?? false
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
    var errorMessage: String? = nil
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
            } else if let error = errorMessage, notes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange.opacity(0.7))

                    Text("Failed to Load Notes")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
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
    @State private var showingReportAlert = false

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
        .contextMenu {
            if canDelete {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    showingReportAlert = true
                } label: {
                    Label("Report Comment", systemImage: "flag")
                }
            }
        }
        .alert("Delete Note", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this note?")
        }
        .alert("Report Comment", isPresented: $showingReportAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Report", role: .destructive) {
                let subject = "Inappropriate Comment Report"
                let body = "I would like to report the following comment as inappropriate:\n\nComment by: \(note.userName)\nComment: \(note.text)\n\nDetails:\n[Please describe the issue here]"
                let mailto = "mailto:support@playerpath.app?subject=\(subject)&body=\(body)"
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: mailto) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Report this comment to PlayerPath support for review?")
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
    @State private var isSaving = false
    @FocusState private var isTextEditorFocused: Bool

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
                        .focused($isTextEditorFocused)
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
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            isSaving = true
                            isTextEditorFocused = false
                            onSave(noteText.trimmingCharacters(in: .whitespacesAndNewlines), timestamp)
                            dismiss()
                        }
                        .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isTextEditorFocused = false
                    }
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
    @Published var isPlayerReady = false
    @Published var annotations: [VideoAnnotation] = []
    @Published var isLoadingAnnotations = false
    @Published var errorMessage: String?
    @Published var playbackRate: Double = 1.0
    var shouldResumeOnActive = false
    private var durationTask: Task<Void, Never>?

    var currentPlaybackTime: Double {
        player?.currentTime().seconds ?? 0.0
    }
    
    init(video: CoachVideoItem, folder: SharedFolder) {
        self.video = video
        self.folder = folder
    }

    deinit {
        statusObservation = nil
    }

    private var statusObservation: NSKeyValueObservation?

    func loadVideo() async {
        isLoading = true
        isPlayerReady = false

        // Prefer a short-lived signed URL; fall back to the stored permanent URL
        let playbackURLString: String
        do {
            playbackURLString = try await SecureURLManager.shared.getSecureVideoURL(
                fileName: video.fileName,
                folderID: folder.id ?? ""
            )
        } catch {
            playbackURLString = video.firebaseStorageURL
        }

        guard let url = URL(string: playbackURLString) else {
            isLoading = false
            return
        }

        let newPlayer = AVPlayer(url: url)
        player = newPlayer

        // Observe the player item's status so we don't hide the loading
        // indicator until the player has actually buffered enough to play.
        statusObservation = nil  // Remove old KVO before setting up new one
        statusObservation = newPlayer.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isPlayerReady = true
                    self.isLoading = false
                case .failed:
                    self.isLoading = false
                    self.errorMessage = item.error?.localizedDescription ?? "Failed to load video"
                default:
                    break
                }
            }
        }
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

            // Mirror coach feedback to the unified comment thread so the athlete sees it
            // in their practice/clip view. videoID == VideoClip.id.uuidString (same Firestore doc).
            if isCoachComment {
                try? await ClipCommentService.shared.postComment(
                    clipId: videoID,
                    text: text,
                    authorId: userID,
                    authorName: userName,
                    authorRole: "coach"
                )
            }

            Haptics.success()

            // Notify the folder owner that a coach left feedback
            if isCoachComment {
                let athleteID = folder.ownerAthleteID
                await ActivityNotificationService.shared.postCoachCommentNotification(
                    videoFileName: video.fileName,
                    folderID: folder.id ?? "",
                    videoID: videoID,
                    coachID: userID,
                    coachName: userName,
                    athleteID: athleteID,
                    notePreview: text
                )
            }

        } catch {
            errorMessage = "Failed to add note: \(error.localizedDescription)"
            Haptics.error()
        }
    }
    
    func deleteAnnotation(_ annotation: VideoAnnotation) async {
        do {
            guard let videoID = video.id as String?,
                  let annotationID = annotation.id else { return }

            try await FirestoreManager.shared.deleteAnnotation(videoID: videoID, annotationID: annotationID)

            annotations.removeAll { $0.id == annotationID }

            Haptics.success()

        } catch {
            errorMessage = "Failed to delete note: \(error.localizedDescription)"
            Haptics.error()
        }
    }

    // MARK: - Video Playback Control

    @Published var videoDuration: Double?
    private var timeObserver: Any?

    func startTimeObserver() {
        guard let player = player else { return }

        // Observe duration (cancel any previous task to prevent accumulation)
        durationTask?.cancel()
        if let currentItem = player.currentItem {
            durationTask = Task {
                do {
                    let duration = try await currentItem.asset.load(.duration)
                    if !Task.isCancelled {
                        self.videoDuration = duration.seconds
                    }
                } catch {
                }
            }
        }

        // Observe current time — reapply playback rate whenever the player starts playing,
        // since VideoPlayer's native controls reset rate to 1.0 on play.
        let interval = CMTime(seconds: 1.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                let currentRate = Float(self.playbackRate)
                if player.timeControlStatus == .playing, player.rate != currentRate {
                    player.rate = currentRate
                }
            }
        }
    }

    func stopTimeObserver() {
        durationTask?.cancel()
        durationTask = nil
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    func seekToTimestamp(_ timestamp: Double) {
        let time = CMTime(seconds: timestamp, preferredTimescale: 600)
        // Use default tolerance — frame-accurate seeking (.zero) is unnecessarily expensive
        player?.seek(to: time)
        player?.play()
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        // Only apply if player is active; re-applied automatically on next play
        if player?.timeControlStatus == .playing {
            player?.rate = Float(rate)
        }
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
                    annotationCount: nil,
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
