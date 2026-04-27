//
//  PlayResultOverlayView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import AVKit
import UIKit

struct PlayResultOverlayView: View {
    let videoURL: URL
    let athlete: Athlete?
    let game: Game?
    let practice: Practice?
    let clipOrientation: VideoOrientation
    let onSave: (PlayResultType?, Double?, String?, AthleteRole) -> Void
    let onCancel: () -> Void

    @State private var selectedResult: PlayResultType?
    @State private var showingConfirmation = false
    @State private var recordingMode: AthleteRole

    @State private var thumbnail: UIImage?
    @State private var videoMetadata: VideoMetadata?
    @State private var metadataTask: Task<Void, Never>?
    @State private var thumbnailTask: Task<Void, Never>?
    @State private var showContent = false
    @State private var isSaving = false
    @State private var pitchSpeedText = ""
    @State private var pitchType: String = "fastball"
    @FocusState private var pitchSpeedFocused: Bool

    private var isLandscape: Bool { clipOrientation.isLandscape }

    init(
        videoURL: URL,
        athlete: Athlete?,
        game: Game?,
        practice: Practice?,
        clipOrientation: VideoOrientation,
        onSave: @escaping (PlayResultType?, Double?, String?, AthleteRole) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.videoURL = videoURL
        self.athlete = athlete
        self.game = game
        self.practice = practice
        self.clipOrientation = clipOrientation
        self.onSave = onSave
        self.onCancel = onCancel
        self._recordingMode = State(initialValue: athlete?.primaryRole ?? .batter)
    }

    var body: some View {
        ZStack {
            // Static Thumbnail Background
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = thumbnail {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.black
                    }
                }
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.25))
                .onAppear {
                    loadThumbnail()
                    loadVideoMetadata()
                }
                .onDisappear {
                    metadataTask?.cancel()
                    metadataTask = nil
                    thumbnailTask?.cancel()
                    thumbnailTask = nil
                }

                // Video metadata badge — safe area aware
                if let metadata = videoMetadata {
                    VideoMetadataView(metadata: metadata)
                        .padding(16)
                        .padding(.top, 16)
                        .padding(.trailing, 0)
                }
            }

            // Info Header — safe area inset so it clears Dynamic Island / status bar
            VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            if let game = game {
                                HStack(spacing: 8) {
                                    Image(systemName: "baseball.diamond.bases")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                    Text("vs \(game.opponent)")
                                        .font(.headingLarge)
                                        .foregroundColor(.white)
                                }
                                if let date = game.date {
                                    HStack(spacing: 6) {
                                        Image(systemName: "calendar")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.6))
                                        Text(date, style: .date)
                                            .font(.bodyMedium)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                } else {
                                    Text("No date")
                                        .font(.bodyMedium)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            } else if let practice = practice {
                                HStack(spacing: 8) {
                                    Image(systemName: practice.type.icon)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                    Text("\(practice.type.displayName) Practice")
                                        .font(.headingLarge)
                                        .foregroundColor(.white)
                                }
                                if let date = practice.date {
                                    HStack(spacing: 6) {
                                        Image(systemName: "calendar")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.6))
                                        Text(date, style: .date)
                                            .font(.bodyMedium)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                } else {
                                    Text("No date")
                                        .font(.bodyMedium)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            if let athlete = athlete {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.fill")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.5))
                                    Text(athlete.name)
                                        .font(.bodySmall)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.leading, isLandscape ? 72 : 104)
                    .padding(.trailing, 20)
                    .padding(.top, isLandscape ? 28 : 16)
                    .padding(.bottom, 20)
                    .accessibilitySortPriority(2)
                    .background(alignment: .top) {
                        LinearGradient(
                            colors: [Color.black.opacity(0.7), Color.black.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .top)
                    }
                    Spacer()
            }

            // Play Result Selection Overlay
            if isLandscape {
                landscapeOverlayPanel
            } else {
                portraitOverlayPanel
            }

            // Back button — top-leading, safe area aware
            VStack {
                HStack {
                    Button {
                        Haptics.warning()
                        onCancel()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            Text("Back")
                                .font(.bodyLarge)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial))
                    }
                    .accessibilityLabel("Go back")
                    .disabled(isSaving)
                    Spacer()
                }
                .padding(.horizontal, 16)
                Spacer()
            }
            .padding(.top, isLandscape ? 28 : 16)

            // Saving overlay
            if isSaving {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Saving...")
                        .font(.headingMedium)
                        .foregroundColor(.white)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSaving)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showContent = true
            }
        }
        .confirmationDialog(
            "Confirm Play Result",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save", role: .none) {
                guard let result = selectedResult else { return }
                isSaving = true
                onSave(result, parsedPitchSpeed, parsedPitchType, recordingMode)
                selectedResult = nil
                // Reset after a timeout in case the parent doesn't dismiss this overlay
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    isSaving = false
                }
            }
            Button("Cancel", role: .cancel) {
                selectedResult = nil
            }
        } message: {
            Text("Save this play as a \(selectedResult?.displayName ?? "play")?")
        }
    }

    // MARK: - Portrait panel

    private var portraitOverlayPanel: some View {
        GeometryReader { geo in
            ScrollView {
                VStack {
                    Spacer(minLength: 0)
                    glassPanel
                        .padding(.horizontal, 16)
                        .accessibilitySortPriority(1)
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 16) }
    }

    // MARK: - Landscape panel

    private var landscapeOverlayPanel: some View {
        HStack(spacing: 0) {
            Spacer()
            ScrollView(showsIndicators: false) {
                glassPanel
                    .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: 420, maxHeight: .infinity)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Shared glass panel content

    private var glassPanel: some View {
        VStack(spacing: 18) {
            // Header
            VStack(spacing: 6) {
                Text("Select Play Result")
                    .font(.headingLarge)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(practice != nil ? "Add a result to track statistics" : "Choose what happened on this play")
                    .font(.bodySmall)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)

            // Recording Mode Picker
            PlayResultModePicker(selection: $recordingMode)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                .onChange(of: recordingMode) { _, _ in
                    selectedResult = nil
                    pitchSpeedFocused = false
                }

            // Pitch Speed Input (pitcher mode only)
            if recordingMode == .pitcher {
                HStack(spacing: 12) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    TextField("", text: $pitchSpeedText, prompt: Text("Pitch Speed").foregroundStyle(.white.opacity(0.4)))
                        .keyboardType(.decimalPad)
                        .focused($pitchSpeedFocused)
                        .foregroundColor(.white)
                        .font(.headingMedium)
                        .frame(maxWidth: .infinity)
                    Text("MPH")
                        .font(.custom("Inter18pt-Bold", size: 12, relativeTo: .caption))
                        .foregroundColor(.white.opacity(0.6))

                    if pitchSpeedFocused {
                        Button {
                            pitchSpeedFocused = false
                        } label: {
                            Text("Done")
                                .font(.headingMedium)
                                .foregroundColor(.brandNavy)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)

                // Pitch Type Picker
                HStack(spacing: 0) {
                    PitchTypeButton(title: "Fastball", isSelected: pitchType == "fastball") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            pitchType = "fastball"
                        }
                        Haptics.light()
                    }
                    PitchTypeButton(title: "Off-Speed", isSelected: pitchType == "offspeed") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            pitchType = "offspeed"
                        }
                        Haptics.light()
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.1)))
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
            }

            // Play Result Grid
            VStack(spacing: 12) {
                if recordingMode == .batter {
                    battingResultsSection
                } else {
                    pitchingResultsSection
                }
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)

            // Action Buttons
            HStack(spacing: 12) {
                PlayResultActionButton(title: "Cancel", icon: "xmark", style: .secondary) {
                    Haptics.warning()
                    onCancel()
                }
                .disabled(isSaving)
                .accessibilityLabel("Cancel")
                .accessibilityHint("Dismiss without saving a play result")

                PlayResultActionButton(
                    title: practice != nil ? "Save Video" : "Skip & Save",
                    icon: "checkmark",
                    style: .primary
                ) {
                    isSaving = true
                    onSave(nil, parsedPitchSpeed, parsedPitchType, recordingMode)
                }
                .disabled(isSaving)
                .accessibilityLabel(practice != nil ? "Save Video Only" : "Skip and Save")
                .accessibilityHint("Save without a play result")
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial)
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
                .strokeBorder(
                    LinearGradient.glassBorder,
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
    }

    // MARK: - Batting Results Section

    private var battingResultsSection: some View {
        VStack(spacing: 14) {
            // Hits Section
            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "baseball.fill", title: "HITS", color: .green)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        PlayResultButton(result: .single, isSelected: selectedResult == .single) { selectResult(.single) }
                        PlayResultButton(result: .double, isSelected: selectedResult == .double) { selectResult(.double) }
                    }
                    HStack(spacing: 10) {
                        PlayResultButton(result: .triple, isSelected: selectedResult == .triple) { selectResult(.triple) }
                        PlayResultButton(result: .homeRun, isSelected: selectedResult == .homeRun) { selectResult(.homeRun) }
                    }
                }
            }

            PlayResultDivider()

            // Walk Section
            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "figure.walk", title: "WALK", color: .brandNavy)

                PlayResultButton(result: .walk, isSelected: selectedResult == .walk, fullWidth: true) {
                    selectResult(.walk)
                }
                PlayResultButton(result: .batterHitByPitch, isSelected: selectedResult == .batterHitByPitch, fullWidth: true) {
                    selectResult(.batterHitByPitch)
                }
            }

            PlayResultDivider()

            // Outs Section
            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "xmark.circle.fill", title: "OUTS", color: .red)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        PlayResultButton(result: .strikeout, isSelected: selectedResult == .strikeout) { selectResult(.strikeout) }
                        PlayResultButton(result: .groundOut, isSelected: selectedResult == .groundOut) { selectResult(.groundOut) }
                    }
                    HStack(spacing: 10) {
                        PlayResultButton(result: .flyOut, isSelected: selectedResult == .flyOut) { selectResult(.flyOut) }
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - Pitching Results Section

    private var pitchingResultsSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "figure.baseball", title: "PITCH RESULT", color: .purple)

                HStack(spacing: 10) {
                    PlayResultButton(result: .ball, isSelected: selectedResult == .ball) { selectResult(.ball) }
                    PlayResultButton(result: .strike, isSelected: selectedResult == .strike) { selectResult(.strike) }
                }
            }

            PlayResultDivider()

            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "baseball.fill", title: "HITS ALLOWED", color: .green)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        PlayResultButton(result: .pitchingSingleAllowed, isSelected: selectedResult == .pitchingSingleAllowed) { selectResult(.pitchingSingleAllowed) }
                        PlayResultButton(result: .pitchingDoubleAllowed, isSelected: selectedResult == .pitchingDoubleAllowed) { selectResult(.pitchingDoubleAllowed) }
                    }
                    HStack(spacing: 10) {
                        PlayResultButton(result: .pitchingTripleAllowed, isSelected: selectedResult == .pitchingTripleAllowed) { selectResult(.pitchingTripleAllowed) }
                        PlayResultButton(result: .pitchingHomeRunAllowed, isSelected: selectedResult == .pitchingHomeRunAllowed) { selectResult(.pitchingHomeRunAllowed) }
                    }
                }
            }

            PlayResultDivider()

            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "xmark.circle.fill", title: "OUTS", color: .red)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        PlayResultButton(result: .pitchingStrikeout, isSelected: selectedResult == .pitchingStrikeout) { selectResult(.pitchingStrikeout) }
                        PlayResultButton(result: .groundOut, isSelected: selectedResult == .groundOut) { selectResult(.groundOut) }
                    }
                    HStack(spacing: 10) {
                        PlayResultButton(result: .flyOut, isSelected: selectedResult == .flyOut) { selectResult(.flyOut) }
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }

            PlayResultDivider()

            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "figure.walk", title: "WALK", color: .brandNavy)

                PlayResultButton(result: .pitchingWalk, isSelected: selectedResult == .pitchingWalk, fullWidth: true) {
                    selectResult(.pitchingWalk)
                }
            }

            PlayResultDivider()

            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "exclamationmark.triangle.fill", title: "SPECIAL", color: .orange)

                HStack(spacing: 10) {
                    PlayResultButton(result: .hitByPitch, isSelected: selectedResult == .hitByPitch) { selectResult(.hitByPitch) }
                    PlayResultButton(result: .wildPitch, isSelected: selectedResult == .wildPitch) { selectResult(.wildPitch) }
                }
            }
        }
    }

    private var parsedPitchSpeed: Double? {
        guard recordingMode == .pitcher, !pitchSpeedText.isEmpty else { return nil }
        return Double(pitchSpeedText)
    }

    private var parsedPitchType: String? {
        guard recordingMode == .pitcher else { return nil }
        return pitchType
    }

    private func selectResult(_ result: PlayResultType) {
        selectedResult = result
        Haptics.medium()
        showingConfirmation = true
    }
}

extension PlayResultOverlayView {
    private func loadThumbnail() {
        guard thumbnail == nil else { return }
        let maxSize: CGSize = clipOrientation.isLandscape
            ? CGSize(width: 640, height: 360)
            : CGSize(width: 360, height: 640)
        thumbnailTask = Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = maxSize
            if let cgImage = try? await generator.image(at: .zero).image {
                guard !Task.isCancelled else { return }
                let image = UIImage(cgImage: cgImage)
                await MainActor.run {
                    thumbnail = image
                }
            }
        }
    }

    private func loadVideoMetadata() {
        guard videoMetadata == nil else { return }

        metadataTask = Task.detached(priority: .userInitiated) {
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

                    resolutionString = RecordingQuality.resolutionName(width: width, height: height)
                }
            }

            guard !Task.isCancelled else { return }
            let metadata = VideoMetadata(
                duration: durationSeconds,
                fileSize: fileSize,
                resolution: resolutionString
            )
            await MainActor.run {
                videoMetadata = metadata
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
        practice: nil,
        clipOrientation: .portrait,
        onSave: { _, _, _, _ in },
        onCancel: { }
    )
}
