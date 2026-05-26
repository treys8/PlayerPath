//
//  ClubPickerEditorView.swift
//  PlayerPath
//
//  Sheet for retro-tagging or editing a golf clip's club. Parallels
//  PlayResultEditorView's structure (current-tag display, grouped picker,
//  confirmation dialog) but writes `clip.club` instead of `clip.playResult`.
//  No statistics recalculation — golf clips don't feed StatisticsService.
//

import SwiftUI
import SwiftData

struct ClubPickerEditorView: View {
    let clip: VideoClip
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var selectedClub: Club?
    @State private var showingConfirmation = false
    @State private var errorMessage: String?
    @State private var showingError = false

    init(clip: VideoClip, modelContext: ModelContext) {
        self.clip = clip
        self.modelContext = modelContext
        _selectedClub = State(initialValue: clip.club)
    }

    private var isTagging: Bool { clip.club == nil }

    private var canSave: Bool {
        selectedClub != clip.club
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Current club
                    VStack(spacing: 12) {
                        Text("Current Club")
                            .font(.headingMedium)
                            .foregroundColor(.secondary)

                        if let current = clip.club {
                            Text(current.displayName)
                                .font(.displayMedium)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(current.category.color.opacity(0.15))
                                )
                                .foregroundColor(current.category.color)
                        } else {
                            Text("No club recorded")
                                .font(.headingLarge)
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                    }
                    .padding(.top)

                    Divider()

                    Text(isTagging ? "Select Club" : "Select New Club")
                        .font(.headingLarge)

                    // Picker sections (Woods / Irons / Wedges / Putter)
                    VStack(spacing: 18) {
                        ForEach(Club.Category.allCases, id: \.self) { category in
                            ClubPickerSection(category: category, selected: selectedClub) { club in
                                selectedClub = club
                                Haptics.medium()
                            }
                        }
                    }
                    .padding(.horizontal, 4)

                    // Remove option (only when editing, not tagging)
                    if !isTagging {
                        Button {
                            selectedClub = nil
                            showingConfirmation = true
                        } label: {
                            Label("Remove Club Tag", systemImage: "xmark.circle")
                                .font(.labelLarge)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                                )
                                .foregroundColor(.red)
                        }
                    }

                    // Save button
                    Button {
                        showingConfirmation = true
                    } label: {
                        Text(isTagging ? "Save" : "Save Changes")
                            .font(.headingMedium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.brandNavy)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1.0 : 0.5)
                    .padding(.top, 4)
                }
                .padding(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isTagging ? "Tag Club" : "Edit Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Confirm Changes",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Save", role: .none) { saveChanges() }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let selected = selectedClub {
                    Text("Tag this clip as \(selected.displayName)?")
                } else {
                    Text("Remove club tag from this clip?")
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
        let prevClub = clip.club
        let prevPlayResult = clip.playResult
        clip.club = selectedClub
        // Either/or invariant: a clip is tagged with EITHER a PlayResult OR
        // a Club. Detach the stale PlayResult relationship — matches the
        // PlayResultEditorView pattern. PlayResult models aren't queried
        // independently anywhere, so orphans are invisible to stats.
        if selectedClub != nil, prevPlayResult != nil {
            clip.playResult = nil
        }
        clip.needsSync = true

        do {
            try modelContext.save()
            Haptics.success()
            dismiss()
        } catch {
            clip.club = prevClub
            clip.playResult = prevPlayResult
            Haptics.warning()
            errorMessage = "Could not save club tag. Please try again."
            showingError = true
        }
    }
}
