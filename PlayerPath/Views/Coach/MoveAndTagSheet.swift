//
//  MoveAndTagSheet.swift
//  PlayerPath
//
//  Sheet shown when a coach shares an instruction video with an athlete.
//  Allows adding instruction notes, tags, and drill type before sharing.
//

import SwiftUI

struct MoveAndTagSheet: View {
    let item: CoachRecordingItem
    let onShare: (String?, [String], String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var notes: String
    @State private var tags: [String] = []
    @State private var drillType: String?
    @State private var showingTagEditor = false

    init(item: CoachRecordingItem, onShare: @escaping (String?, [String], String?) -> Void) {
        self.item = item
        self.onShare = onShare
        _notes = State(initialValue: item.metadata.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                // Destination info
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.baseball")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.athleteName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(item.folderName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Share To")
                }

                // Instruction notes — the key field
                Section {
                    TextField("What should the athlete focus on?", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Instruction Notes")
                } footer: {
                    Text("Your notes will be displayed alongside the video so the athlete can read them while watching.")
                }

                // Drill type
                Section {
                    Picker("Drill Type", selection: Binding(
                        get: { drillType ?? "" },
                        set: { drillType = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("None").tag("")
                        ForEach(DrillType.allCases, id: \.self) { drill in
                            Text(drill.displayName).tag(drill.rawValue)
                        }
                    }
                } header: {
                    Text("Categorize")
                }

                // Tags
                Section {
                    if tags.isEmpty {
                        Button {
                            showingTagEditor = true
                        } label: {
                            Label("Add Tags", systemImage: "tag")
                                .foregroundColor(.green)
                        }
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                TagChip(text: tag, isSelected: true, onTap: {})
                            }
                        }
                        .padding(.vertical, 4)

                        Button {
                            showingTagEditor = true
                        } label: {
                            Label("Edit Tags", systemImage: "pencil")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                } header: {
                    Text("Tags")
                }
            }
            .navigationTitle("Share with Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        onShare(trimmedNotes.isEmpty ? nil : trimmedNotes, tags, drillType)
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingTagEditor) {
                VideoTagEditor(selectedTags: $tags, drillType: $drillType)
            }
        }
    }
}
