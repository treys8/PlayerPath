//
//  PlayResultEditorView.swift
//  PlayerPath
//
//  Sheet for editing a video clip's play result (hit type, out type, walk, etc.)
//

import SwiftUI
import SwiftData

struct PlayResultEditorView: View {
    let clip: VideoClip
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var selectedResult: PlayResultType?
    @State private var mode: AthleteRole
    @State private var showingConfirmation = false
    @State private var errorMessage: String?
    @State private var showingError = false

    init(clip: VideoClip, modelContext: ModelContext) {
        self.clip = clip
        self.modelContext = modelContext
        _selectedResult = State(initialValue: clip.playResult?.type)
        let initialMode: AthleteRole = {
            if let existing = clip.playResult?.type {
                return existing.isPitchingResult ? .pitcher : .batter
            }
            return clip.athlete?.primaryRole ?? .batter
        }()
        _mode = State(initialValue: initialMode)
    }

    private var isTagging: Bool { clip.playResult == nil }

    private var canSave: Bool {
        guard let selected = selectedResult else { return false }
        return selected != clip.playResult?.type
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Current result
                    VStack(spacing: 12) {
                        Text("Current Play Result")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        if let currentResult = clip.playResult?.type {
                            HStack {
                                Image(systemName: currentResult.iconName)
                                    .font(.title)
                                    .foregroundColor(currentResult.color)
                                Text(currentResult.displayName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(currentResult.color.opacity(0.1))
                            )
                        } else {
                            Text("No result recorded")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                    }
                    .padding(.top)

                    Divider()

                    // New result selection
                    VStack(spacing: 16) {
                        Text(isTagging ? "Select Play Result" : "Select New Result")
                            .font(.headline)

                        Picker("Mode", selection: $mode) {
                            Text("Batter").tag(AthleteRole.batter)
                            Text("Pitcher").tag(AthleteRole.pitcher)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { _, _ in
                            selectedResult = nil
                            Haptics.light()
                        }

                        VStack(spacing: 12) {
                            if mode == .batter {
                                battingResultsSection
                            } else {
                                pitchingResultsSection
                            }

                            // Remove result option (only when editing, not tagging)
                            if !isTagging {
                                Button {
                                    selectedResult = nil
                                    showingConfirmation = true
                                } label: {
                                    Label("Remove Play Result", systemImage: "xmark.circle")
                                        .font(.body.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                                        )
                                        .foregroundColor(.red)
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding()

                        // Save button
                        Button {
                            showingConfirmation = true
                        } label: {
                            Text(isTagging ? "Save" : "Save Changes")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.brandNavy)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(!canSave)
                        .opacity(canSave ? 1.0 : 0.5)
                        .padding(.top, 8)
                    }
            }
            .padding(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isTagging ? "Tag Play Result" : "Edit Play Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Confirm Changes",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Save", role: .none) {
                    saveChanges()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let selected = selectedResult {
                    Text("Change play result to \(selected.displayName)?")
                } else {
                    Text("Remove play result from this clip?")
                }
            }
            .alert("Save Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Result Sections

    private var battingResultsSection: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Hits")
                LazyVGrid(columns: twoColumnGrid, spacing: 8) {
                    ForEach([PlayResultType.single, .double, .triple, .homeRun], id: \.self) { result in
                        resultButton(result)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Walk")
                resultButton(.walk, fullWidth: true)
                resultButton(.batterHitByPitch, fullWidth: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Outs")
                LazyVGrid(columns: twoColumnGrid, spacing: 8) {
                    ForEach([PlayResultType.strikeout, .groundOut, .flyOut], id: \.self) { result in
                        resultButton(result)
                    }
                }
            }
        }
    }

    private var pitchingResultsSection: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Pitches")
                LazyVGrid(columns: twoColumnGrid, spacing: 8) {
                    ForEach([PlayResultType.ball, .strike], id: \.self) { result in
                        resultButton(result)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Outs")
                LazyVGrid(columns: twoColumnGrid, spacing: 8) {
                    ForEach([PlayResultType.pitchingStrikeout, .groundOut, .flyOut], id: \.self) { result in
                        resultButton(result)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Walk")
                resultButton(.pitchingWalk, fullWidth: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Special")
                LazyVGrid(columns: twoColumnGrid, spacing: 8) {
                    ForEach([PlayResultType.hitByPitch, .wildPitch], id: \.self) { result in
                        resultButton(result)
                    }
                }
            }
        }
    }

    private var twoColumnGrid: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
    }

    private func resultButton(_ result: PlayResultType, fullWidth: Bool = false) -> some View {
        PlayResultEditButton(
            result: result,
            isSelected: selectedResult == result,
            isCurrent: clip.playResult?.type == result,
            fullWidth: fullWidth
        ) {
            selectedResult = result
            Haptics.medium()
        }
    }

    private func saveChanges() {
        let prevResult = clip.playResult
        let prevType = clip.playResult?.type

        if let selected = selectedResult {
            if let existing = clip.playResult {
                existing.type = selected
            } else {
                let newResult = PlayResult(type: selected)
                clip.playResult = newResult
            }
        } else {
            clip.playResult = nil
        }

        do {
            try modelContext.save()

            if let athlete = clip.athlete {
                if let game = clip.game {
                    do {
                        try StatisticsService.shared.recalculateGameStatistics(for: game, context: modelContext)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "VideoPlayerView.recalcGameStats", showAlert: false)
                    }
                }
                do {
                    try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "VideoPlayerView.recalcAthleteStats", showAlert: false)
                }
            }

            Haptics.success()
            dismiss()
        } catch {
            // Roll back in-memory mutation
            if let prev = prevResult {
                prev.type = prevType ?? prev.type
                clip.playResult = prev
            } else {
                clip.playResult = nil
            }
            Haptics.warning()
            errorMessage = "Could not save play result. Please try again."
            showingError = true
        }
    }
}

struct PlayResultEditButton: View {
    let result: PlayResultType
    let isSelected: Bool
    let isCurrent: Bool
    var fullWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(result.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .center)

                if isCurrent {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? result.color : result.color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isCurrent ? Color.green.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
            .foregroundColor(isSelected ? .white : result.color)
        }
        .buttonStyle(.plain)
    }
}
