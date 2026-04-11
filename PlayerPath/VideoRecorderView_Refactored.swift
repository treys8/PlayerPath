//
//  VideoRecorderView_Refactored.swift
//  PlayerPath
//
//  Created by Assistant on 10/27/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import os

private let recorderLog = Logger(subsystem: "com.playerpath.app", category: "VideoRecorder")
import AVKit
import PhotosUI
import CoreMedia
import UIKit
import Combine
import Network

// MARK: - VideoRecorderView_Refactored

@MainActor
struct VideoRecorderView_Refactored: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let athlete: Athlete?
    let game: Game?
    let practice: Practice?
    
    // Service objects
    @StateObject private var uploadService = VideoUploadService()
    @StateObject private var networkMonitor = NetworkMonitor()

    // State management
    @State private var recordedVideoURL: URL?
    @State private var showingPhotoPicker = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var showingDiscardConfirmation = false
    @State private var pendingDismissAction: (() -> Void)?
    @State private var saveTask: Task<Void, Never>?
    @State private var showingSaveError = false
    @State private var showingTrimmer = false
    @State private var trimmedVideoURL: URL?
    @State private var uploadFlowShowingPlayResult = false

    // System monitoring
    @State private var availableStorageGB: Double = 0

    init(athlete: Athlete?, game: Game? = nil, practice: Practice? = nil) {
        self.athlete = athlete
        self.game = game
        self.practice = practice
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            networkStatusBanner
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedVideoItem, matching: .videos, preferredItemEncoding: .compatible)
        .onChange(of: selectedVideoItem) { _, newItem in
            handleSelectedVideo(newItem)
        }
        .onChange(of: showingPhotoPicker) { _, isShowing in
            if !isShowing && selectedVideoItem == nil && recordedVideoURL == nil && !showingTrimmer {
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $showingTrimmer) {
            videoTrimmerView
        }
        .confirmationDialog(
            "Discard Clip?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                pendingDismissAction?()
                pendingDismissAction = nil
                cleanupAndDismiss()
            }
            Button("Keep", role: .cancel) {
                pendingDismissAction = nil
            }
        } message: {
            Text("This clip won't be saved to PlayerPath. Your original video in Photos is not affected.")
        }
        .task {
            networkMonitor.startMonitoring()
            checkAvailableStorage()
            showingPhotoPicker = true
        }
        .onDisappear {
            networkMonitor.stopMonitoring()
        }
    }
    
    @ViewBuilder
    private var videoTrimmerView: some View {
        ZStack {
            if let videoURL = recordedVideoURL {
                if uploadFlowShowingPlayResult {
                    let finalVideoURL = trimmedVideoURL ?? videoURL
                    if practice != nil {
                        PracticeVideoSaveView(
                            videoURL: finalVideoURL,
                            athlete: athlete,
                            practice: practice,
                            onSave: { note, completion in
                                saveVideoWithResult(videoURL: finalVideoURL, playResult: nil, note: note, onError: {
                                    completion() // Reset PracticeVideoSaveView spinner so user can retry
                                }) {
                                    completion()
                                    uploadFlowShowingPlayResult = false
                                    showingTrimmer = false
                                    PlayerPathAppDelegate.orientationLock = .allButUpsideDown
                                    dismiss()
                                }
                            },
                            onDiscard: {
                                pendingDismissAction = {
                                    VideoFileManager.cleanup(url: videoURL)
                                    if let trimmed = trimmedVideoURL {
                                        VideoFileManager.cleanup(url: trimmed)
                                    }
                                    self.recordedVideoURL = nil
                                    self.trimmedVideoURL = nil
                                    self.uploadFlowShowingPlayResult = false
                                    self.showingTrimmer = false
                                }
                                showingDiscardConfirmation = true
                            }
                        )
                    } else {
                        PlayResultOverlayView(
                            videoURL: finalVideoURL,
                            athlete: athlete,
                            game: game,
                            practice: practice,
                            onSave: { result, pitchSpeed, pitchType, role in
                                saveVideoWithResult(videoURL: finalVideoURL, playResult: result, pitchSpeed: pitchSpeed, pitchType: pitchType, role: role) {
                                    uploadFlowShowingPlayResult = false
                                    showingTrimmer = false
                                    PlayerPathAppDelegate.orientationLock = .allButUpsideDown
                                    dismiss()
                                }
                            },
                            onCancel: {
                                pendingDismissAction = {
                                    VideoFileManager.cleanup(url: videoURL)
                                    if let trimmed = trimmedVideoURL {
                                        VideoFileManager.cleanup(url: trimmed)
                                    }
                                    self.recordedVideoURL = nil
                                    self.trimmedVideoURL = nil
                                    self.uploadFlowShowingPlayResult = false
                                    self.showingTrimmer = false
                                }
                                showingDiscardConfirmation = true
                            }
                        )
                    }
                } else {
                    PreUploadTrimmerView(
                        videoURL: videoURL,
                        onSave: { trimmedURL in
                            trimmedVideoURL = trimmedURL
                            lockPortrait()
                            uploadFlowShowingPlayResult = true
                        },
                        onSkip: {
                            trimmedVideoURL = nil
                            lockPortrait()
                            uploadFlowShowingPlayResult = true
                        },
                        onCancel: {
                            pendingDismissAction = {
                                VideoFileManager.cleanup(url: videoURL)
                                if let trimmed = trimmedVideoURL {
                                    VideoFileManager.cleanup(url: trimmed)
                                }
                                self.recordedVideoURL = nil
                                self.trimmedVideoURL = nil
                                self.showingTrimmer = false
                            }
                            showingDiscardConfirmation = true
                        }
                    )
                }
            }
        }
        .alert("Save Failed", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The video could not be saved. Please try recording again.")
        }
    }

    // MARK: - Network / Storage Banner

    @ViewBuilder
    private var networkStatusBanner: some View {
        VStack(spacing: 0) {
            // Network status
            if !networkMonitor.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                    Text("No internet connection")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text("Videos will save locally")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.9))
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No internet connection. Videos will save locally.")
            }
            
            // Low storage warning (critical)
            if availableStorageGB > 0 && availableStorageGB < 1.0 {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill.badge.exclamationmark")
                        .font(.caption)
                    Text("Low storage: \(String(format: "%.1f", availableStorageGB)) GB free")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.9))
                )
                .padding(.horizontal)
                .padding(.top, networkMonitor.isConnected ? 8 : 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Low storage warning. \(String(format: "%.1f", availableStorageGB)) gigabytes free.")
            }

            Spacer()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: networkMonitor.isConnected)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: availableStorageGB)
    }
    
    // MARK: - Business Logic

    private func handleSelectedVideo(_ item: PhotosPickerItem?) {
        Task {
            let result = await uploadService.processSelectedVideo(item)
            switch result {
            case .success(let videoURL):
                recordedVideoURL = videoURL

                let duration = await getVideoDuration(videoURL)
                let autoShowTrimmer = UserDefaults.standard.bool(forKey: "autoShowTrimmer")
                let skipShortClips = UserDefaults.standard.bool(forKey: "skipTrimmerForShortClips")

                if !autoShowTrimmer && duration < 15 && skipShortClips {
                    // Skip trimmer — go straight to tagging
                    uploadFlowShowingPlayResult = true
                }
                showingTrimmer = true
                Haptics.medium()
            case .failure:
                break
            }
        }
    }

    private func getVideoDuration(_ url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return CMTimeGetSeconds(duration)
        } catch {
            return 0
        }
    }
    
    private func checkAvailableStorage() {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory() as String)
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                availableStorageGB = Double(capacity) / StorageConstants.bytesPerGBDouble
            }
        } catch {
            ErrorHandlerService.shared.handle(error, context: "VideoRecorder.checkStorage", showAlert: false)
        }
    }

    private func saveVideoWithResult(videoURL: URL, playResult: PlayResultType?, pitchSpeed: Double? = nil, pitchType: String? = nil, role: AthleteRole = .batter, note: String? = nil, onError: (() -> Void)? = nil, onComplete: @escaping () -> Void) {
        guard let athlete = athlete else {
            Haptics.error()
            onComplete() // Still dismiss UI to avoid stuck state
            return
        }

        // If a save is already in progress, let it finish (cancelling mid-copy
        // would orphan a partial file in Clips/ with no database record)
        guard saveTask == nil else {
            return
        }

        // Save in background — video file stays on disk until copy completes.
        // Success feedback and dismiss happen AFTER the save confirms.
        saveTask = Task {
            guard !Task.isCancelled else {
                await MainActor.run { self.saveTask = nil }
                return
            }

            do {
                _ = try await ClipPersistenceService().saveClip(
                    from: videoURL,
                    playResult: playResult,
                    pitchSpeed: pitchSpeed,
                    pitchType: pitchType,
                    role: role,
                    note: note,
                    context: modelContext,
                    athlete: athlete,
                    game: game,
                    practice: practice
                )

                // Save succeeded — now dismiss
                await MainActor.run {
                    Haptics.success()
                    UIAccessibility.post(notification: .announcement, argument: "Video saved successfully")
                    VideoFileManager.cleanup(url: videoURL)
                    if let trimmed = self.trimmedVideoURL {
                        VideoFileManager.cleanup(url: trimmed)
                    }
                    self.recordedVideoURL = nil
                    self.trimmedVideoURL = nil
                    self.saveTask = nil
                    onComplete()
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run { self.saveTask = nil }
                    return
                }
                await MainActor.run {
                    Haptics.error()
                    ErrorHandlerService.shared.handle(error, context: "VideoRecorderView.saveVideoWithResult", showAlert: false)
                    self.saveTask = nil
                    onError?()
                    self.showingSaveError = true
                }
            }
        }
    }
    
    /// Locks the UI to portrait immediately before presenting an overlay view.
    /// Called synchronously so the orientation is already set when SwiftUI renders the overlay.
    private func lockPortrait() {
        PlayerPathAppDelegate.orientationLock = .portrait
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
    }

    private func cleanupAndDismiss() {
        saveTask?.cancel()
        saveTask = nil

        Task { @MainActor in
            if let videoURL = recordedVideoURL {
                VideoFileManager.cleanup(url: videoURL)
            }
            if let trimmedURL = trimmedVideoURL {
                VideoFileManager.cleanup(url: trimmedURL)
            }
            recordedVideoURL = nil
            trimmedVideoURL = nil
            uploadFlowShowingPlayResult = false
            showingTrimmer = false
            showingPhotoPicker = false
            selectedVideoItem = nil
            PlayerPathAppDelegate.orientationLock = .allButUpsideDown
            dismiss()
        }
    }
}

// MARK: - Supporting Views

struct GuidelineItem: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.1))
        )
    }
}


// MARK: - Network Monitoring

@MainActor class NetworkMonitor: ObservableObject {
    @Published var isConnected: Bool = true
    @Published var connectionType: NWInterface.InterfaceType?

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "NetworkMonitor")

    func startMonitoring() {
        guard monitor == nil else { return }

        let pathMonitor = NWPathMonitor()
        monitor = pathMonitor

        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type

                if path.status == .satisfied {
                    if let type = path.availableInterfaces.first?.type {
                        _ = self?.interfaceTypeName(type) ?? "unknown"
                    }
                } else {
                }
            }
        }
        pathMonitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
    }

    private func interfaceTypeName(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: return "WiFi"
        case .cellular: return "Cellular"
        case .wiredEthernet: return "Ethernet"
        case .loopback: return "Loopback"
        case .other: return "Other"
        @unknown default: return "Unknown"
        }
    }

    var isOnWiFi: Bool {
        connectionType == .wifi
    }

    var isOnCellular: Bool {
        connectionType == .cellular
    }
}

#Preview("Recorder - Game") {
    // Minimal inline mock for preview purposes
    let mockGame = Game(date: Date(), opponent: "Rivals")
    VideoRecorderView_Refactored(athlete: nil, game: mockGame, practice: nil)
}

#Preview("Recorder - Practice") {
    // Minimal inline mock for preview purposes
    let mockPractice = Practice(date: Date())
    VideoRecorderView_Refactored(athlete: nil, game: nil, practice: mockPractice)
}

// MARK: - AVPlayerLayer UIViewRepresentable
// Uses AVPlayerLayer directly instead of AVKit's VideoPlayer (which wraps AVPlayerViewController).
// AVPlayerViewController interferes with SwiftUI's fullScreenCover geometry when nested,
// causing incorrect frame calculation in the presented view. AVPlayerLayer has no such issue.

private struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? PlayerUIView else { return }
        view.playerLayer.player = player
    }

    private class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer {
            guard let playerLayer = layer as? AVPlayerLayer else {
                fatalError("Expected AVPlayerLayer but got \(type(of: layer)) — layerClass override missing")
            }
            return playerLayer
        }
    }
}

// MARK: - Pre-Upload Trimmer View

struct PreUploadTrimmerView: View {
    let videoURL: URL
    let onSave: (URL) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void
    var onDiscard: (() -> Void)? = nil
    /// When true, hides the "Use Full Video" button. Used by the re-trim flow
    /// in `RetrimSavedClipFlow` where that action doesn't make sense (the user
    /// already has the full clip saved and is editing it).
    var hideSkipButton: Bool = false

    @State private var player: AVPlayer?
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var duration: Double = 0
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var currentTime: Double = 0
    @State private var isPlaying = true
    @State private var timeObserver: Any?
    @State private var showContent = false
    @State private var videoEndObserver: NSObjectProtocol?
    @State private var durationTask: Task<Void, Never>?

    @Environment(\.verticalSizeClass) private var vSizeClass
    private var isLandscape: Bool { vSizeClass == .compact }

    var body: some View {
        ZStack {
            // Full-screen video background — fills physical screen edges
            if let player = player {
                AVPlayerLayerView(player: player)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.15))
            } else {
                Color.black.ignoresSafeArea()
            }

            if isLandscape {
                landscapeTrimmerLayout
            } else {
                portraitTrimmerLayout
            }
        }
        .onAppear {
            setupPlayer()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showContent = true
            }
        }
        .onDisappear {
            cleanup()
        }
    }

    // MARK: - Back button

    private var backButtonView: some View {
        Button {
            Haptics.warning()
            onCancel()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                Text("Back")
                    .font(.body)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.ultraThinMaterial))
        }
    }

    // MARK: - Portrait layout

    private var portraitTrimmerLayout: some View {
        VStack {
            HStack {
                backButtonView
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer()

            trimGlassPanel
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Landscape layout

    private var landscapeTrimmerLayout: some View {
        HStack(spacing: 0) {
            // Left column: back button
            VStack {
                HStack {
                    backButtonView
                    Spacer()
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding(.leading, 16)
            .frame(maxWidth: 120)

            Spacer()

            // Right: scrollable trim controls
            ScrollView(showsIndicators: false) {
                trimGlassPanel
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: 380)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Trim glass panel

    private var trimGlassPanel: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 6) {
                Text("Trim Video")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Drag to set start and end points")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)

            // Play/pause preview control
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .accessibilityLabel(isPlaying ? "Pause preview" : "Play preview")
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)

            // Time indicators
            HStack {
                TrimTimeBadge(label: "START", time: formatTime(startTime), color: .green)
                Spacer()
                TrimTimeBadge(label: "DURATION", time: formatTime(endTime - startTime), color: .brandNavy)
                Spacer()
                TrimTimeBadge(label: "END", time: formatTime(endTime), color: .red)
            }
            .padding(.horizontal, 4)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)

            // Trim sliders — only show when duration is long enough to trim
            if duration >= 0.6 {
                // Safe bounds: ensure upper > lower by at least one step (0.1)
                let startSliderMax = max(0.1, endTime - 0.5)
                let endSliderMin = min(duration - 0.1, startTime + 0.5)
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.right.to.line")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                            .frame(width: 20)
                        Slider(value: $startTime, in: 0...startSliderMax, step: 0.1)
                            .tint(.green)
                            .onChange(of: startTime) { _, newValue in
                                seekTo(time: newValue)
                            }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "arrow.left.to.line")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.red)
                            .frame(width: 20)
                        Slider(value: $endTime, in: endSliderMin...duration, step: 0.1)
                            .tint(.red)
                            .onChange(of: endTime) { _, newValue in
                                seekTo(time: newValue)
                            }
                    }
                }
                .padding(.horizontal, 4)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 30)
            }

            if let error = exportError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            // Action buttons
            VStack(spacing: 10) {
                Button {
                    Task { await exportTrimmedVideo() }
                } label: {
                    HStack(spacing: 8) {
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Trimming...")
                                .font(.body.weight(.semibold))
                        } else {
                            Image(systemName: "scissors")
                                .font(.body.weight(.semibold))
                            Text("Save Trimmed")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient.primaryButton)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(LinearGradient.glassBorder, lineWidth: 1)
                    )
                    .shadow(color: Color.brandNavy.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .disabled(isExporting || endTime - startTime < 0.5)
                .opacity(isExporting || endTime - startTime < 0.5 ? 0.6 : 1)

                if !hideSkipButton {
                    Button {
                        Haptics.light()
                        onSkip()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "film")
                                .font(.body.weight(.semibold))
                            Text("Use Full Video")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(LinearGradient.glassBorder, lineWidth: 1)
                        )
                    }
                    .disabled(isExporting)
                }

                if let onDiscard {
                    Button {
                        Haptics.warning()
                        onDiscard()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .font(.body.weight(.semibold))
                            Text("Discard")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.red.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .disabled(isExporting)
                }
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient.glassDark)
                VStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient.glassShine)
                        .frame(height: 100)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(LinearGradient.glassBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
    }

    private func setupPlayer() {
        let newPlayer = AVPlayer(url: videoURL)
        newPlayer.isMuted = true
        player = newPlayer
        newPlayer.play()

        // Add time observer for playback position. Also enforces the trim
        // end: when playback crosses endTime, loop back to startTime so the
        // user previews only the range they've selected.
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            currentTime = seconds
            // Only enforce the end point during active playback. When the user
            // is paused (e.g. scrubbing the end slider), leave the current
            // time alone so they can see the exact frame at their chosen end.
            if isPlaying, endTime > 0, seconds >= endTime - 0.05 {
                player?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                player?.play()
            }
        }

        // Loop video at end
        videoEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { _ in
            newPlayer.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
            newPlayer.play()
            isPlaying = true
        }

        // Fix W: Store the task so cleanup() can cancel it if the view is dismissed
        // before the asset load completes.
        durationTask = Task {
            let asset = AVURLAsset(url: videoURL)
            do {
                let loadedDuration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(loadedDuration)
                await MainActor.run {
                    self.duration = seconds
                    self.startTime = 0
                    self.endTime = seconds
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.exportError = "Unable to load video: \(error.localizedDescription)"
                }
            }
        }
    }

    private func seekTo(time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        player?.pause()
        isPlaying = false
    }

    private func togglePlayback() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // If we're at or past endTime, rewind to startTime before resuming.
            if currentTime >= endTime - 0.05 {
                player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
            }
            player.play()
            isPlaying = true
        }
        Haptics.light()
    }

    private func cleanup() {
        // Fix W: Cancel the duration-loading task before tearing down the player.
        durationTask?.cancel()
        durationTask = nil
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = videoEndObserver {
            NotificationCenter.default.removeObserver(observer)
            videoEndObserver = nil
        }
        player?.pause()
        player = nil
    }

    private func exportTrimmedVideo() async {
        isExporting = true
        exportError = nil
        do {
            let outputURL = try await VideoTrimExporter.export(
                sourceURL: videoURL,
                startTime: startTime,
                endTime: endTime
            )
            await MainActor.run {
                isExporting = false
                Haptics.success()
                onSave(outputURL)
            }
        } catch {
            await MainActor.run {
                isExporting = false
                exportError = error.localizedDescription
            }
        }
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, milliseconds)
    }
}

// MARK: - Trim Time Badge

private struct TrimTimeBadge: View {
    let label: String
    let time: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(color.opacity(0.9))
            Text(time)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(0.3), lineWidth: 1)
        )
    }
}

