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
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    @State private var isDragging = false
    @State private var playbackSpeed: PlaybackSpeed = .normal
    @State private var showControls = true
    @State private var timeObserver: Any?
    @State private var endObserver: (any NSObjectProtocol)?
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video layer
                VideoPlayerRepresentable(player: player)
                    .onTapGesture {
                        togglePlayPause()
                        showControlsTemporarily()
                    }

                // Custom controls overlay
                if showControls {
                    VStack {
                        Spacer()

                        // Control panel
                        VStack(spacing: 12) {
                            // Timeline scrubber
                            timelineView

                            // Play controls
                            playbackControlsView

                            // Speed controls
                            speedControlsView
                        }
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.7), .black.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
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
    }

    // MARK: - Timeline View

    private var timelineView: some View {
        VStack(spacing: 4) {
            Slider(
                value: $currentTime,
                in: 0...duration,
                onEditingChanged: { dragging in
                    isDragging = dragging
                    if !dragging {
                        seek(to: currentTime)
                    }
                    showControlsTemporarily()
                }
            )
            .tint(.white)

            HStack {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .foregroundColor(.white)

                Spacer()

                Text(formatTime(duration))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Playback Controls

    private var playbackControlsView: some View {
        HStack(spacing: 32) {
            // Frame backward
            Button {
                stepBackward()
                showControlsTemporarily()
            } label: {
                Image(systemName: "backward.frame.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }

            // Skip back 5 seconds
            Button {
                skip(by: -5.0)
                showControlsTemporarily()
            } label: {
                Image(systemName: "gobackward.5")
                    .font(.title)
                    .foregroundColor(.white)
            }

            // Play/Pause
            Button {
                togglePlayPause()
                showControlsTemporarily()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white)
            }

            // Skip forward 5 seconds
            Button {
                skip(by: 5.0)
                showControlsTemporarily()
            } label: {
                Image(systemName: "goforward.5")
                    .font(.title)
                    .foregroundColor(.white)
            }

            // Frame forward
            Button {
                stepForward()
                showControlsTemporarily()
            } label: {
                Image(systemName: "forward.frame.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
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
            }
        }
    }

    // MARK: - Player Control Methods

    private func setupPlayer() {
        // Get duration asynchronously
        if let currentItem = player.currentItem {
            Task {
                if let loadedDuration = try? await currentItem.asset.load(.duration) {
                    await MainActor.run {
                        self.duration = CMTimeGetSeconds(loadedDuration)
                    }
                }
            }
        }

        // Add time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            if !isDragging {
                currentTime = CMTimeGetSeconds(time)
            }
        }

        // Observe playback state
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
        }

        // Set initial playing state
        isPlaying = player.rate > 0
    }

    private func cleanup() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        hideControlsTask?.cancel()
    }

    private func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        Haptics.light()
    }

    private func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func skip(by seconds: Double) {
        let newTime = max(0, min(currentTime + seconds, duration))
        seek(to: newTime)
        Haptics.light()
    }

    private func stepForward() {
        // Step forward by 1 frame (assuming 30 fps)
        let frameTime = 1.0 / 30.0
        let newTime = min(currentTime + frameTime, duration)
        seek(to: newTime)
        player.pause()
        isPlaying = false
        Haptics.light()
    }

    private func stepBackward() {
        // Step backward by 1 frame (assuming 30 fps)
        let frameTime = 1.0 / 30.0
        let newTime = max(currentTime - frameTime, 0)
        seek(to: newTime)
        player.pause()
        isPlaying = false
        Haptics.light()
    }

    private func setPlaybackSpeed(_ speed: PlaybackSpeed) {
        playbackSpeed = speed
        player.rate = Float(speed.value)
        if speed.value > 0 {
            isPlaying = true
        }
        Haptics.light()
    }

    private func showControlsTemporarily() {
        showControls = true
        hideControlsTask?.cancel()

        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if !Task.isCancelled {
                withAnimation {
                    showControls = false
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Playback Speed Enum

enum PlaybackSpeed: CaseIterable {
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
        controller.videoGravity = .resizeAspect
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
