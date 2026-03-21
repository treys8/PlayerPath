//
//  MoveAndTagSheet.swift
//  PlayerPath
//
//  Sheet shown when a coach shares a recording with an athlete.
//  Allows adding tags and drill type before sharing.
//

import SwiftUI

struct MoveAndTagSheet: View {
    let item: CoachRecordingItem
    let onShare: ([String], String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String] = []
    @State private var drillType: String?
    @State private var showingTagEditor = false

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
                } footer: {
                    Text("Tags help organize and filter videos later.")
                }
            }
            .navigationTitle("Share Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        onShare(tags, drillType)
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
