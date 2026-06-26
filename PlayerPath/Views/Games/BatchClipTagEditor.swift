//
//  BatchClipTagEditor.swift
//  PlayerPath
//
//  Multi-select editor to assign a hole (golf rounds / practice rounds) or a
//  club (range sessions) to several clips at once. Reached from the "Unassigned"
//  (no hole) and "Untagged" (no club) buckets in HoleDetailView / ClubDetailView
//  — the home for clips recorded before scoring or imported without a tag.
//
//  Writes only existing fields (holeNumber / club) on existing clips, marks each
//  needsSync, and saves; SyncCoordinator pushes the change. (holeNumber now
//  rides the update path too — see VideoCloudManager.updateVideoMetadata and
//  SyncCoordinator.videoMetadataMatches.)
//

import SwiftUI
import SwiftData

struct BatchClipTagEditor: View {
    enum Mode: Equatable {
        case hole(maxHoles: Int)
        case club
    }

    let clips: [VideoClip]
    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccent) private var ppAccent

    @State private var selectedClipIDs: Set<UUID>
    @State private var targetHole: Int = 1
    @State private var targetClub: Club?

    init(clips: [VideoClip], mode: Mode) {
        self.clips = clips
        self.mode = mode
        // Default to all selected — the common case is "tag everything here".
        _selectedClipIDs = State(initialValue: Set(clips.map(\.id)))
    }

    private var isHoleMode: Bool {
        if case .hole = mode { return true }
        return false
    }

    private var title: String { isHoleMode ? "Assign Hole" : "Assign Club" }

    private var allSelected: Bool { selectedClipIDs.count == clips.count }

    private var canApply: Bool {
        guard !selectedClipIDs.isEmpty else { return false }
        if case .club = mode { return targetClub != nil }
        return true
    }

    private var applyLabel: String {
        let count = selectedClipIDs.count
        return "Assign to \(count) clip\(count == 1 ? "" : "s")"
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(isHoleMode ? "Hole" : "Club").smallCapsLabel()) {
                    switch mode {
                    case .hole(let maxHoles):
                        NumberChipGrid(range: 1...max(1, maxHoles), selected: targetHole, par: nil) { value in
                            targetHole = value
                        }
                        .padding(.vertical, 4)
                    case .club:
                        VStack(spacing: 14) {
                            ForEach(Club.Category.allCases, id: \.self) { category in
                                ClubPickerSection(category: category, selected: targetClub) { club in
                                    targetClub = club
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: clipsHeader) {
                    ForEach(clips) { clip in
                        Button { toggle(clip) } label: { clipRow(clip) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: apply) {
                    Text(applyLabel)
                        .font(.headingMedium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canApply)
                .padding()
                .background(.ultraThinMaterial)
            }
        }
    }

    private var clipsHeader: some View {
        HStack {
            Text("Clips (\(selectedClipIDs.count) of \(clips.count))").smallCapsLabel()
            Spacer()
            Button(allSelected ? "Deselect All" : "Select All") {
                selectedClipIDs = allSelected ? [] : Set(clips.map(\.id))
            }
            .font(.bodySmall)
            .textCase(nil)
        }
    }

    private func clipRow(_ clip: VideoClip) -> some View {
        let isOn = selectedClipIDs.contains(clip.id)
        return HStack(spacing: 12) {
            VideoThumbnailView(
                clip: clip,
                size: CGSize(width: 56, height: 56),
                cornerRadius: 8,
                showPlayResult: false,
                showHighlight: false,
                showSeason: false,
                showContext: false,
                showDuration: true,
                fillsContainer: false
            )
            .frame(width: 56, height: 56)

            Text(clipTimeLabel(clip))
                .font(.bodyMedium)
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isOn ? ppAccent : Theme.textTertiary)
        }
        .contentShape(Rectangle())
    }

    private func clipTimeLabel(_ clip: VideoClip) -> String {
        guard let date = clip.createdAt else { return "Clip" }
        return DateFormatter.shortTime.string(from: date)
    }

    private func toggle(_ clip: VideoClip) {
        if selectedClipIDs.contains(clip.id) {
            selectedClipIDs.remove(clip.id)
        } else {
            selectedClipIDs.insert(clip.id)
        }
    }

    private func apply() {
        guard canApply else { return }
        for clip in clips where selectedClipIDs.contains(clip.id) {
            switch mode {
            case .hole:
                clip.holeNumber = targetHole
            case .club:
                clip.club = targetClub
            }
            clip.needsSync = true
        }
        if ErrorHandlerService.shared.saveContext(modelContext, caller: "BatchClipTagEditor") {
            // A batch club tag may have cleared an event's last untagged clip —
            // drop its pending "tag your clips" nudge (self-guards per event).
            for clip in clips where selectedClipIDs.contains(clip.id) {
                ClipTaggingReminderService.shared.cancelIfEventFullyTagged(for: clip)
            }
            Haptics.success()
        } else {
            Haptics.error()
        }
        dismiss()
    }
}
