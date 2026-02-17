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
    let onSave: (PlayResultType?, Double?, AthleteRole) -> Void
    let onCancel: () -> Void
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var hSizeClass
    
    @State private var selectedResult: PlayResultType?
    @State private var showingConfirmation = false
    @State private var player = AVPlayer()
    @State private var recordingMode: AthleteRole = .batter
    
    @State private var isPlaying = true
    @State private var videoMetadata: VideoMetadata?
    @State private var metadataTask: Task<Void, Never>?
    @State private var isLooping = false
    @State private var hasLooped = false
    @State private var showContent = false
    @State private var videoEndObserver: NSObjectProtocol?
    @State private var isSaving = false
    @State private var pitchSpeedText = ""

    init(videoURL: URL, athlete: Athlete?, game: Game? = nil, practice: Practice? = nil, onSave: @escaping (PlayResultType?, Double?, AthleteRole) -> Void, onCancel: @escaping () -> Void) {
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
                                addVideoEndObserver()
                            }
                            .onDisappear {
                                player.pause()
                                player.replaceCurrentItem(with: nil)
                                isPlaying = false
                                if let task = metadataTask {
                                    task.cancel()
                                    metadataTask = nil
                                }
                                removeVideoEndObserver()
                            }
                        
                        // Video metadata badge and replay indicator
                        VStack(alignment: .trailing, spacing: 8) {
                            if let metadata = videoMetadata {
                                VideoMetadataView(metadata: metadata)
                            }

                            if hasLooped {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 10))
                                    Text("Replaying")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.9))
                                )
                                .shadow(radius: 2)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(16)
                        .padding(.top, 60) // Position higher and make room for toolbar
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

                    VStack(spacing: 18) {
                        // Header
                        VStack(spacing: 8) {
                            Text("Select Play Result")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .accessibilityAddTraits(.isHeader)

                            Text(practice != nil ? "Add a result to track statistics" : "Choose what happened on this play")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)

                        // Recording Mode Picker - Custom styled
                        PlayResultModePicker(selection: $recordingMode)
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 20)

                        // Pitch Speed Input (pitcher mode only)
                        if recordingMode == .pitcher {
                            HStack(spacing: 12) {
                                Image(systemName: "speedometer")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))

                                TextField("", text: $pitchSpeedText, prompt: Text("Pitch Speed").foregroundStyle(.white.opacity(0.4)))
                                    .keyboardType(.decimalPad)
                                    .foregroundColor(.white)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)

                                Text("MPH")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 20)
                        }

                        // Play Result Grid - Conditional based on mode
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
                            PlayResultActionButton(
                                title: "Cancel",
                                icon: "xmark",
                                style: .secondary
                            ) {
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
                                Haptics.success()
                                onSave(nil, parsedPitchSpeed, recordingMode)
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
                            // Glass background
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(.ultraThinMaterial)

                            // Dark gradient overlay
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.2),
                                            Color.black.opacity(0.4)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                            // Top shine
                            VStack {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.15), .clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                                    .frame(height: 100)
                                Spacer()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
                    .padding(.horizontal, 16)
                    .accessibilitySortPriority(1)
                    .onAppear {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showContent = true
                        }
                    }

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
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.2), value: isSaving)
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
                    isSaving = true
                    onSave(result, parsedPitchSpeed, recordingMode)
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
        }
    }

    // MARK: - Batting Results Section

    private var battingResultsSection: some View {
        VStack(spacing: 14) {
            // Hits Section
            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "baseball.fill", title: "HITS", color: .green)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach([PlayResultType.single, .double, .triple, .homeRun], id: \.self) { result in
                        PlayResultButton(
                            result: result,
                            isSelected: selectedResult == result
                        ) {
                            selectResult(result)
                        }
                    }
                }
            }

            PlayResultDivider()

            // Walk Section
            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "figure.walk", title: "WALK", color: .blue)

                PlayResultButton(
                    result: .walk,
                    isSelected: selectedResult == .walk,
                    fullWidth: true
                ) {
                    selectResult(.walk)
                }
            }

            PlayResultDivider()

            // Outs Section
            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "xmark.circle.fill", title: "OUTS", color: .red)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach([PlayResultType.strikeout, .groundOut, .flyOut], id: \.self) { result in
                        PlayResultButton(
                            result: result,
                            isSelected: selectedResult == result
                        ) {
                            selectResult(result)
                        }
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

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    PlayResultButton(
                        result: .ball,
                        isSelected: selectedResult == .ball
                    ) {
                        selectResult(.ball)
                    }
                    PlayResultButton(
                        result: .strike,
                        isSelected: selectedResult == .strike
                    ) {
                        selectResult(.strike)
                    }
                }
            }

            PlayResultDivider()

            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "xmark.circle.fill", title: "OUTS", color: .red)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach([PlayResultType.strikeout, .groundOut, .flyOut], id: \.self) { result in
                        PlayResultButton(
                            result: result,
                            isSelected: selectedResult == result
                        ) {
                            selectResult(result)
                        }
                    }
                }
            }

            PlayResultDivider()

            VStack(alignment: .leading, spacing: 10) {
                PlayResultSectionHeader(icon: "exclamationmark.triangle.fill", title: "SPECIAL", color: .orange)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    PlayResultButton(
                        result: .hitByPitch,
                        isSelected: selectedResult == .hitByPitch
                    ) {
                        selectResult(.hitByPitch)
                    }
                    PlayResultButton(
                        result: .wildPitch,
                        isSelected: selectedResult == .wildPitch
                    ) {
                        selectResult(.wildPitch)
                    }
                }
            }
        }
    }

    private var parsedPitchSpeed: Double? {
        guard recordingMode == .pitcher, !pitchSpeedText.isEmpty else { return nil }
        return Double(pitchSpeedText)
    }

    private func selectResult(_ result: PlayResultType) {
        selectedResult = result
        Haptics.medium()
        player.pause()
        isPlaying = false
        showingConfirmation = true
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
        case .ball: return "circle"
        case .strike: return "xmark.circle.fill"
        case .hitByPitch: return "figure.fall"
        case .wildPitch: return "arrow.up.right.and.arrow.down.left"
        }
    }

    var uiColor: Color {
        switch self {
        case .single, .double, .triple, .homeRun: return .green
        case .walk: return .blue
        case .strikeout, .groundOut, .flyOut: return .red
        case .ball: return .orange
        case .strike: return .green
        case .hitByPitch: return .purple
        case .wildPitch: return .red
        }
    }

    var accessibilityLabel: String { displayName }
}

struct PlayResultButton: View {
    let result: PlayResultType
    let isSelected: Bool
    var fullWidth: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    // Glow behind icon when selected
                    if isSelected {
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .blur(radius: 8)
                    }

                    Image(systemName: result.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                }

                // Label
                Text(result.displayName)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.5), radius: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 56)
            .background(
                ZStack {
                    // Base gradient
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    result.uiColor,
                                    result.uiColor.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Shine overlay
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isSelected ? 0.25 : 0.15),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )

                    // Selection glow
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isSelected ? 0.6 : 0.3),
                                Color.white.opacity(isSelected ? 0.3 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: result.uiColor.opacity(isSelected ? 0.6 : 0.3), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            .scaleEffect(isPressed ? 0.95 : (isSelected ? 1.02 : 1.0))
        }
        .buttonStyle(PlayResultButtonStyle(isPressed: $isPressed))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(result.accessibilityLabel))
        .accessibilityHint(Text("Selects this play result and asks for confirmation"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PlayResultButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

// MARK: - Section Header

struct PlayResultSectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Divider

struct PlayResultDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.2), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.vertical, 2)
    }
}

// MARK: - Custom Mode Picker

struct PlayResultModePicker: View {
    @Binding var selection: AthleteRole

    var body: some View {
        HStack(spacing: 0) {
            ModeButton(
                title: "Batter",
                icon: "figure.baseball",
                isSelected: selection == .batter
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selection = .batter
                }
                Haptics.light()
            }

            ModeButton(
                title: "Pitcher",
                icon: "figure.cricket",
                isSelected: selection == .pitcher
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selection = .pitcher
                }
                Haptics.light()
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
    }

    struct ModeButton: View {
        let title: String
        let icon: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))

                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 2)
                        }
                    }
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Premium Action Button

struct PlayResultActionButton: View {
    let title: String
    let icon: String
    let style: ActionStyle
    let action: () -> Void

    enum ActionStyle {
        case primary
        case secondary
        case destructive
    }

    @State private var isPressed = false

    private var shadowColor: Color {
        switch style {
        case .primary: return .blue.opacity(0.4)
        case .secondary: return .clear
        case .destructive: return .red.opacity(0.4)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .secondary:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.15))
        case .destructive:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.red, .red.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    var body: some View {
        Button(action: {
            Haptics.medium()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))

                Text(title)
                    .font(.body.weight(.semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(backgroundView)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: shadowColor, radius: 8, x: 0, y: 4)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(ActionButtonStyle(isPressed: $isPressed))
    }

    struct ActionButtonStyle: ButtonStyle {
        @Binding var isPressed: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .onChange(of: configuration.isPressed) { _, newValue in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        isPressed = newValue
                    }
                }
        }
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
                MetadataBadge(icon: "video", text: resolution, color: .purple)
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
    private func addVideoEndObserver() {
        removeVideoEndObserver()
        videoEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            // Loop the video from the beginning
            player?.seek(to: .zero)
            player?.play()

            hasLooped = true
            isLooping = true

            // Auto-hide replay indicator after 3 seconds
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    withAnimation {
                        hasLooped = false
                    }
                }
            }
        }
    }

    private func removeVideoEndObserver() {
        if let observer = videoEndObserver {
            NotificationCenter.default.removeObserver(observer)
            videoEndObserver = nil
        }
    }

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
        onSave: { _, _, _ in },
        onCancel: { }
    )
}
