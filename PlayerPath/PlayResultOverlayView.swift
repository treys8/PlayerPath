//
//  PlayResultOverlayView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import AVKit
import UIKit

struct PlayResultOverlayView: View {
    let videoURL: URL
    let athlete: Athlete?
    let game: Game?
    let practice: Practice?
    let onSave: (PlayResultType?) -> Void
    let onCancel: () -> Void
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var hSizeClass
    
    @State private var selectedResult: PlayResultType?
    @State private var showingConfirmation = false
    @State private var player = AVPlayer()
    
    @State private var isPlaying = true
    @State private var videoMetadata: VideoMetadata?
    @State private var metadataTask: Task<Void, Never>?
    
    init(videoURL: URL, athlete: Athlete?, game: Game? = nil, practice: Practice? = nil, onSave: @escaping (PlayResultType?) -> Void, onCancel: @escaping () -> Void) {
        self.videoURL = videoURL
        self.athlete = athlete
        self.game = game
        self.practice = practice
        self.onSave = onSave
        self.onCancel = onCancel
        self._player = State(initialValue: AVPlayer(url: videoURL))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Video Player Background with Play/Pause Button
                ZStack(alignment: .bottomLeading) {
                    ZStack(alignment: .topTrailing) {
                        VideoPlayer(player: player)
                            .allowsHitTesting(false)
                            .overlay(Color.black.opacity(0.25))
                            .onAppear {
                                player.play()
                                isPlaying = true
                                loadVideoMetadata()
                            }
                            .onDisappear {
                                player.pause()
                                player.replaceCurrentItem(with: nil)
                                isPlaying = false
                                metadataTask?.cancel()
                            }
                        
                        // Video metadata badge
                        if let metadata = videoMetadata {
                            VideoMetadataView(metadata: metadata)
                                .padding(16)
                                .padding(.top, 60) // Position higher and make room for toolbar
                        }
                    }
                    
                    Button {
                        if isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                        isPlaying.toggle()
                        Haptics.light()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding(12)
                    .accessibilityLabel(isPlaying ? "Pause video" : "Play video")
                }
                
                // Play Result Selection Overlay
                VStack {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        if practice != nil {
                            Text("Select Play Result")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.8)
                                .lineLimit(1)
                                .accessibilityAddTraits(.isHeader)
                            
                            Text("Add a result to track statistics")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        } else {
                            Text("Select Play Result")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.8)
                                .lineLimit(1)
                                .accessibilityAddTraits(.isHeader)
                            
                            Text("Choose what happened on this play")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        
                        // Play Result Grid - Improved Layout
                        VStack(spacing: 12) {
                            // Hits Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Hits")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 4)
                                    .accessibilityAddTraits(.isHeader)
                                
                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ], spacing: 8) {
                                    ForEach([PlayResultType.single, .double, .triple, .homeRun], id: \.self) { result in
                                        PlayResultButton(
                                            result: result,
                                            isSelected: selectedResult == result
                                        ) {
                                            selectedResult = result
                                            Haptics.medium()
                                            player.pause()
                                            isPlaying = false
                                            showingConfirmation = true
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.3))
                                .padding(.vertical, 4)
                            
                            // Walk Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Walk")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 4)
                                    .accessibilityAddTraits(.isHeader)
                                
                                PlayResultButton(
                                    result: .walk,
                                    isSelected: selectedResult == .walk,
                                    fullWidth: true
                                ) {
                                    selectedResult = .walk
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    player.pause()
                                    isPlaying = false
                                    showingConfirmation = true
                                }
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.3))
                                .padding(.vertical, 4)
                            
                            // Outs Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Outs")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 4)
                                    .accessibilityAddTraits(.isHeader)
                                
                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ], spacing: 8) {
                                    ForEach([PlayResultType.strikeout, .groundOut, .flyOut], id: \.self) { result in
                                        PlayResultButton(
                                            result: result,
                                            isSelected: selectedResult == result
                                        ) {
                                            selectedResult = result
                                            Haptics.medium()
                                            player.pause()
                                            isPlaying = false
                                            showingConfirmation = true
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Action Buttons
                        HStack(spacing: 12) {
                            Button {
                                Haptics.warning()
                                onCancel()
                            } label: {
                                Label("Cancel", systemImage: "xmark")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.15))
                                    )
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Cancel")
                            .accessibilityHint("Dismiss without saving a play result")
                            
                            Button {
                                Haptics.success()
                                onSave(nil)
                            } label: {
                                Label(practice != nil ? "Save Video Only" : "Skip & Save", systemImage: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.blue)
                                    )
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(practice != nil ? "Save Video Only" : "Skip and Save")
                            .accessibilityHint("Save without a play result")
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.black.opacity(0.3),
                                                Color.black.opacity(0.5)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                    )
                    .padding(.horizontal, 16)
                    .accessibilitySortPriority(1)
                    
                    Spacer().frame(height: 50)
                }
                
                // Info Header - Improved Design
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            if let game = game {
                                HStack(spacing: 8) {
                                    Image(systemName: "sportscourt.fill")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Text("vs \(game.opponent)")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                
                                if let date = game.date {
                                    HStack(spacing: 6) {
                                        Image(systemName: "calendar")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.6))
                                        Text(date, style: .date)
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                } else {
                                    Text("Date TBA")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            } else if let practice = practice {
                                HStack(spacing: 8) {
                                    Image(systemName: "figure.baseball")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Text("Practice Session")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                
                                if let date = practice.date {
                                    HStack(spacing: 6) {
                                        Image(systemName: "calendar")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.6))
                                        Text(date, style: .date)
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                } else {
                                    Text("Date TBA")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            
                            if let athlete = athlete {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.fill")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.5))
                                    Text(athlete.name)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                    .accessibilitySortPriority(2)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.7),
                                Color.black.opacity(0.5),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    Spacer()
                }
            }
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                    }
                    .accessibilityLabel("Go back")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    if !showingConfirmation {
                        player.play()
                        isPlaying = true
                    }
                } else {
                    player.pause()
                    isPlaying = false
                }
            }
            .confirmationDialog(
                "Confirm Play Result",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Save", role: .none) {
                    guard let result = selectedResult else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onSave(result)
                    selectedResult = nil
                }
                Button("Cancel", role: .cancel) {
                    selectedResult = nil
                    player.play()
                    isPlaying = true
                }
            } message: {
                Text("Save this play as a \(selectedResult?.displayName ?? "play")?")
            }
            .onChange(of: showingConfirmation) { _, isShowing in
                if isShowing {
                    player.pause()
                    isPlaying = false
                }
            }
        }
    }
}

extension PlayResultType {
    var iconName: String {
        switch self {
        case .single: return "1.circle.fill"
        case .double: return "2.circle.fill"
        case .triple: return "3.circle.fill"
        case .homeRun: return "4.circle.fill"
        case .walk: return "figure.walk"
        case .strikeout: return "k.circle.fill"
        case .groundOut: return "arrow.down.circle.fill"
        case .flyOut: return "arrow.up.circle.fill"
        }
    }
    
    var uiColor: Color {
        switch self {
        case .single, .double, .triple, .homeRun: return .green
        case .walk: return .blue
        case .strikeout, .groundOut, .flyOut: return .red
        }
    }
    
    var accessibilityLabel: String { displayName }
}

struct PlayResultButton: View {
    let result: PlayResultType
    let isSelected: Bool
    var fullWidth: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Label
                Text(result.displayName)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(result.uiColor)
                    .shadow(color: result.uiColor.opacity(0.4), radius: isSelected ? 8 : 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.4 : 0.15), lineWidth: isSelected ? 2 : 1)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .brightness(isSelected ? 0.1 : 0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(result.accessibilityLabel))
        .accessibilityHint(Text("Selects this play result and asks for confirmation"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct OverlayButtonStyle: ButtonStyle {
    let background: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(background.opacity(configuration.isPressed ? 0.7 : 0.8))
            .foregroundColor(.white)
            .cornerRadius(10)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Video Metadata Extension
struct VideoMetadata: Sendable {
    let duration: TimeInterval
    let fileSize: Int64
    let resolution: String?
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedFileSize: String {
        let mb = Double(fileSize) / 1_048_576
        if mb < 1 {
            let kb = Double(fileSize) / 1024
            return String(format: "%.0f KB", kb)
        }
        return String(format: "%.1f MB", mb)
    }
}

struct VideoMetadataView: View {
    let metadata: VideoMetadata
    
    var body: some View {
        HStack(spacing: 12) {
            MetadataBadge(icon: "clock.fill", text: metadata.formattedDuration, color: .blue)
            MetadataBadge(icon: "doc.fill", text: metadata.formattedFileSize, color: .green)
            if let resolution = metadata.resolution {
                MetadataBadge(icon: "video.fill", text: resolution, color: .purple)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Video info: \(metadata.formattedDuration), \(metadata.formattedFileSize)")
    }
}

struct MetadataBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.8))
        )
        .shadow(radius: 2)
    }
}

extension PlayResultOverlayView {
    private func loadVideoMetadata() {
        guard videoMetadata == nil else { return }

        metadataTask = Task {
            let asset = AVURLAsset(url: videoURL)

            // Get duration
            guard !Task.isCancelled else { return }
            let duration = try? await asset.load(.duration)
            let durationSeconds = duration?.seconds ?? 0

            // Get file size
            guard !Task.isCancelled else { return }
            let attributes = try? FileManager.default.attributesOfItem(atPath: videoURL.path)
            let fileSize = attributes?[.size] as? Int64 ?? 0

            // Get resolution
            guard !Task.isCancelled else { return }
            var resolutionString: String?
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                guard !Task.isCancelled else { return }
                let size = try? await track.load(.naturalSize)
                if let size = size {
                    let width = Int(size.width)
                    let height = Int(size.height)

                    // Common resolution names
                    switch (width, height) {
                    case (3840, 2160), (2160, 3840):
                        resolutionString = "4K"
                    case (1920, 1080), (1080, 1920):
                        resolutionString = "1080p"
                    case (1280, 720), (720, 1280):
                        resolutionString = "720p"
                    case (640, 480), (480, 640):
                        resolutionString = "480p"
                    default:
                        resolutionString = "\(width)×\(height)"
                    }
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                videoMetadata = VideoMetadata(
                    duration: durationSeconds,
                    fileSize: fileSize,
                    resolution: resolutionString
                )
            }
        }
    }
}

// MARK: - Preview
#Preview {
    PlayResultOverlayView(
        videoURL: URL(string: "https://sample-videos.com/zip/10/mp4/SampleVideo_1280x720_1mb.mp4")!,
        athlete: nil,
        game: nil,
        onSave: { _ in },
        onCancel: { }
    )
}
