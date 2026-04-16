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
    @State private var showingConfirmation = false
    @State private var errorMessage: String?
    @State private var showingError = false

    init(clip: VideoClip, modelContext: ModelContext) {
        self.clip = clip
        self.modelContext = modelContext
        _selectedResult = State(initialValue: clip.playResult?.type)
    }

    private var isTagging: Bool { clip.playResult == nil }

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
                                    .foregroundColor(currentResult.uiColor)
                                Text(currentResult.displayName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(currentResult.uiColor.opacity(0.1))
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
                        VStack(spacing: 12) {
                            // Hits Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Hits")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)

                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ], spacing: 8) {
                                    ForEach([PlayResultType.single, .double, .triple, .homeRun], id: \.self) { result in
                                        PlayResultEditButton(
                                            result: result,
                                            isSelected: selectedResult == result,
                                            isCurrent: clip.playResult?.type == result
                                        ) {
                                            selectedResult = result
                                            Haptics.medium()
                                        }
                                    }
                                }
                            }

                            // Walk Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Walk")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)

                                PlayResultEditButton(
                                    result: .walk,
                                    isSelected: selectedResult == .walk,
                                    isCurrent: clip.playResult?.type == .walk,
                                    fullWidth: true
                                ) {
                                    selectedResult = .walk
                                    Haptics.medium()
                                }
                            }

                            // Outs Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Outs")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)

                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ], spacing: 8) {
                                    ForEach([PlayResultType.strikeout, .groundOut, .flyOut], id: \.self) { result in
                                        PlayResultEditButton(
                                            result: result,
                                            isSelected: selectedResult == result,
                                            isCurrent: clip.playResult?.type == result
                                        ) {
                                            selectedResult = result
                                            Haptics.medium()
                                        }
                                    }
                                }
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
                        .disabled(selectedResult == clip.playResult?.type)
                        .opacity(selectedResult == clip.playResult?.type ? 0.5 : 1.0)
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
                    .fill(isSelected ? result.uiColor : result.uiColor.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isCurrent ? Color.green.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
            .foregroundColor(isSelected ? .white : result.uiColor)
        }
        .buttonStyle(.plain)
    }
}
