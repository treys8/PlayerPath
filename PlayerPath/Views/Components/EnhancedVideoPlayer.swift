//
//  EnhancedVideoPlayer.swift
//  PlayerPath
//
//  Advanced video player with slow-motion, frame-by-frame, and playback controls
//

import SwiftUI
import AVKit
import Combine

struct EnhancedVideoPlayer: View {
    let player: AVPlayer
    /// Pre-loaded duration from the parent to avoid a redundant asset.load(.duration) call.
    /// Falls back to async loading if not provided (e.g. from contexts that don't pre-load).
    var preloadedDuration: Double?
    /// Called when the user taps the close button (shown in landscape when the nav bar is hidden).
    var onClose: (() -> Void)?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var durationLoaded = false
    @State private var isDragging = false
    @State private var playbackSpeed: PlaybackSpeed = .normal
    @State private var showControls = true
    @State private var timeObserver: Any?
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isAtEnd = false
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(\.scenePhase) private var scenePhase
    private var isLandscape: Bool { vSizeClass == .compact }

    // Zoom
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video layer — scale/offset applied to wrapper so UIKit VC transforms correctly
                VideoPlayerRepresentable(player: player)
                    .scaleEffect(zoomScale, anchor: .center)
                    .offset(panOffset)

                // Transparent gesture capture layer on top of the UIKit view
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastZoomScale
                                    lastZoomScale = value
                                    zoomScale = min(max(zoomScale * delta, 1.0), 4.0)
                                }
                                .onEnded { _ in
                                    lastZoomScale = 1.0
                                    if zoomScale <= 1.0 {
                                        withAnimation(.spring()) {
                                            zoomScale = 1.0
                                            panOffset = .zero
                                            lastPanOffset = .zero
                                        }
                                    }
                                },
                            DragGesture()
                                .onChanged { value in
                                    guard zoomScale > 1.0 else { return }
                                    let maxX = (zoomScale - 1) * geometry.size.width / 2
                                    let maxY = (zoomScale - 1) * geometry.size.height / 2
                                    let newWidth = lastPanOffset.width + value.translation.width
                                    let newHeight = lastPanOffset.height + value.translation.height
                                    panOffset = CGSize(
                                        width: min(max(newWidth, -maxX), maxX),
                                        height: min(max(newHeight, -maxY), maxY)
                                    )
                                    showControlsTemporarily()
                                }
                                .onEnded { _ in
                                    lastPanOffset = panOffset
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            zoomScale = 1.0
                            panOffset = .zero
                            lastPanOffset = .zero
                        }
                    }
                    .onTapGesture {
                        togglePlayPause()
                        showControlsTemporarily()
                    }

                // Custom controls overlay
                if showControls {
                    controlsOverlay
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            setupPlayer()
            showControlsTemporarily()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                // Remove time observer to prevent background CPU usage
                if let observer = timeObserver {
                    player.removeTimeObserver(observer)
                    timeObserver = nil
                }
            } else {
                // Re-add time observer on foreground return if not already present
                if timeObserver == nil {
                    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
                    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                        if !isDragging {
                            currentTime = CMTimeGetSeconds(time)
                        }
                    }
                }
            }
        }
        .onChange(of: preloadedDuration) { _, newDuration in
            // Parent may supply the duration after the view has already appeared
            // (e.g. local-file path loads duration in the background).
            if let d = newDuration, d > 0 {
                duration = d
                durationLoaded = true
                durationTask?.cancel()
                durationTask = nil
            }
        }
        .onReceive(player.publisher(for: \.timeControlStatus)) { status in
            let nowPlaying = status == .playing
            isPlaying = nowPlaying
            // When playback starts, kick off the auto-hide timer.
            // showControlsTemporarily() can't do this itself because isPlaying
            // updates asynchronously after the tap that triggers play.
            if nowPlaying && showControls {
                scheduleControlsHide()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)) { _ in
            isAtEnd = true
            withAnimation { showControls = true }
            hideControlsTask?.cancel()
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        ZStack(alignment: .topTrailing) {
            // Close button in landscape (nav bar is hidden)
            if isLandscape, let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                }
                .accessibilityLabel("Close video player")
                .padding(16)
                .zIndex(1)
            }

            VStack {
                Spacer()

                if isLandscape {
                    landscapeControls
                } else {
                    portraitControls
                }
            }
        }
    }

    // MARK: - Portrait Controls (stacked layout)

    private var portraitControls: some View {
        VStack(spacing: 12) {
            timelineView
            playbackControlsView
            speedControlsView
        }
        .padding()
        .background(controlsGradient)
    }

    // MARK: - Landscape Controls (compact single-row layout)

    private var landscapeControls: some View {
        VStack(spacing: 8) {
            timelineView

            HStack(spacing: 0) {
                // Speed picker on the left
                speedControlsCompact
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Playback controls centered
                playbackControlsView

                // Spacer to balance
                Color.clear
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(controlsGradient)
    }

    private var controlsGradient: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.7), .black.opacity(0.9)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Timeline View

    private var timelineView: some View {
        VStack(spacing: 4) {
            Slider(
                value: $currentTime,
                in: 0...max(duration, 1),
                onEditingChanged: { dragging in
                    isDragging = dragging
                    if dragging {
                        isAtEnd = false
                    }
                    if !dragging {
                        seek(to: currentTime)
                    }
                    showControlsTemporarily()
                }
            )
            .disabled(!durationLoaded)
            .tint(.white)
            .accessibilityLabel("Video position")
            .accessibilityValue("\(formatTime(currentTime)) of \(formatTime(duration))")

            HStack {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .foregroundColor(.white)

                Spacer()

                Text("-\(formatTime(duration - currentTime))")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Playback Controls

    private var playbackControlsView: some View {
        HStack(spacing: isLandscape ? 24 : 32) {
            // Frame backward
            Button {
                stepBackward()
                showControlsTemporarily()
            } label: {
                Image(systemName: "backward.frame.fill")
                    .font(isLandscape ? .body : .title2)
                    .foregroundColor(.white)
            }
            .accessibilityLabel("Step back one frame")

            // Skip back 5 seconds
            Button {
                skip(by: -5.0)
                showControlsTemporarily()
            } label: {
                Image(systemName: "gobackward.5")
                    .font(isLandscape ? .title3 : .title)
                    .foregroundColor(.white)
            }
            .accessibilityLabel("Skip back 5 seconds")

            // Play/Pause/Replay
            Button {
                togglePlayPause()
                showControlsTemporarily()
            } label: {
                Image(systemName: playPauseIcon)
                    .font(.system(size: isLandscape ? 40 : 50))
                    .foregroundColor(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(isPlaying ? "Pause" : isAtEnd ? "Replay" : "Play")

            // Skip forward 5 seconds
            Button {
                skip(by: 5.0)
                showControlsTemporarily()
            } label: {
                Image(systemName: "goforward.5")
                    .font(isLandscape ? .title3 : .title)
                    .foregroundColor(.white)
            }
            .accessibilityLabel("Skip forward 5 seconds")

            // Frame forward
            Button {
                stepForward()
                showControlsTemporarily()
            } label: {
                Image(systemName: "forward.frame.fill")
                    .font(isLandscape ? .body : .title2)
                    .foregroundColor(.white)
            }
            .accessibilityLabel("Step forward one frame")
        }
    }

    private var playPauseIcon: String {
        if isPlaying {
            return "pause.circle.fill"
        } else if isAtEnd {
            return "arrow.counterclockwise.circle.fill"
        } else {
            return "play.circle.fill"
        }
    }

    // MARK: - Speed Controls

    private var speedControlsView: some View {
        HStack(spacing: 8) {
            Text("Speed:")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                Button {
                    setPlaybackSpeed(speed)
                    showControlsTemporarily()
                } label: {
                    Text(speed.displayName)
                        .font(.caption)
                        .fontWeight(playbackSpeed == speed ? .bold : .regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(playbackSpeed == speed ? Color.blue : Color.white.opacity(0.2))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Speed \(speed.displayName)")
                .accessibilityAddTraits(playbackSpeed == speed ? .isSelected : [])
            }
        }
    }

    /// Compact speed picker for landscape — shows current speed as a tappable capsule that cycles through speeds
    private var speedControlsCompact: some View {
        Button {
            cyclePlaybackSpeed()
            showControlsTemporarily()
        } label: {
            Text(playbackSpeed.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
        .accessibilityLabel("Playback speed \(playbackSpeed.displayName)")
        .accessibilityHint("Double tap to cycle speed")
    }

    // MARK: - Player Control Methods

    @State private var durationTask: Task<Void, Never>?

    private func setupPlayer() {
        // Use pre-loaded duration if available; otherwise load asynchronously.
        if let preloaded = preloadedDuration, preloaded > 0 {
            duration = preloaded
            durationLoaded = true
        } else if let currentItem = player.currentItem {
            durationTask = Task {
                if let loadedDuration = try? await currentItem.asset.load(.duration) {
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.duration = CMTimeGetSeconds(loadedDuration)
                            self.durationLoaded = true
                        }
                    }
                }
            }
        }

        // Add time observer (guard against double-add if onAppear fires twice)
        if timeObserver == nil {
            let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                if !isDragging {
                    currentTime = CMTimeGetSeconds(time)
                }
            }
        }
    }

    private func cleanup() {
        player.pause()
        durationTask?.cancel()
        durationTask = nil
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        hideControlsTask?.cancel()
    }

    private func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            // If the video has ended, seek to the beginning and replay
            if isAtEnd {
                isAtEnd = false
                player.seek(to: .zero) { _ in
                    Task { @MainActor in
                        self.player.play()
                        if self.playbackSpeed != .normal {
                            self.player.rate = Float(self.playbackSpeed.value)
                        }
                    }
                }
                Haptics.light()
                return
            }
            player.play()
            if playbackSpeed != .normal {
                player.rate = Float(playbackSpeed.value)
            }
        }
        Haptics.light()
    }

    private func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func skip(by seconds: Double) {
        isAtEnd = false
        let newTime = max(0, min(currentTime + seconds, duration))
        seek(to: newTime)
        Haptics.light()
    }

    private func stepForward() {
        player.currentItem?.step(byCount: 1)
        player.pause()
        Haptics.light()
    }

    private func stepBackward() {
        isAtEnd = false
        player.currentItem?.step(byCount: -1)
        player.pause()
        Haptics.light()
    }

    private func setPlaybackSpeed(_ speed: PlaybackSpeed) {
        playbackSpeed = speed
        if isPlaying {
            player.rate = Float(speed.value)
        }
        Haptics.light()
    }

    private func cyclePlaybackSpeed() {
        let allSpeeds = PlaybackSpeed.allCases
        if let index = allSpeeds.firstIndex(of: playbackSpeed) {
            let next = allSpeeds[(index + 1) % allSpeeds.count]
            setPlaybackSpeed(next)
        }
    }

    private func showControlsTemporarily() {
        withAnimation { showControls = true }
        hideControlsTask?.cancel()

        // Keep controls visible while paused or at end — only auto-hide during playback
        guard isPlaying else { return }
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if !Task.isCancelled && !isDragging && isPlaying {
                withAnimation {
                    showControls = false
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Playback Speed Enum

enum PlaybackSpeed: CaseIterable, Equatable {
    case quarter
    case half
    case normal
    case double

    var value: Double {
        switch self {
        case .quarter: return 0.25
        case .half: return 0.5
        case .normal: return 1.0
        case .double: return 2.0
        }
    }

    var displayName: String {
        switch self {
        case .quarter: return "0.25x"
        case .half: return "0.5x"
        case .normal: return "1x"
        case .double: return "2x"
        }
    }
}

// MARK: - UIKit Video Player Representable

struct VideoPlayerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false // Use custom controls
        controller.videoGravity = .resizeAspectFill
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    if let url = Bundle.main.url(forResource: "sample", withExtension: "mp4") {
        let player = AVPlayer(url: url)
        EnhancedVideoPlayer(player: player)
    } else {
        Text("No preview available")
    }
}
