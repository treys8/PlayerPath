//
//  EnhancedAddNoteView.swift
//  PlayerPath
//
//  Enhanced version of AddNoteView with category picker,
//  quick cue suggestions, and free text.
//

import SwiftUI

struct EnhancedAddNoteView: View {
    let currentTime: Double
    let quickCues: [QuickCue]
    let onSave: (String, Double, AnnotationCategory?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""
    @State private var timestamp: Double
    @State private var selectedCategory: AnnotationCategory?
    @State private var isSaving = false
    @FocusState private var isTextEditorFocused: Bool

    init(currentTime: Double, quickCues: [QuickCue], onSave: @escaping (String, Double, AnnotationCategory?) -> Void) {
        self.currentTime = currentTime
        self.quickCues = quickCues
        self.onSave = onSave
        _timestamp = State(initialValue: currentTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Timestamp
                Section {
                    HStack {
                        Text("Timestamp")
                        Spacer()
                        Text(timestamp.formattedTimestamp)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }

                // Category
                Section("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            CategoryChip(
                                category: nil,
                                isSelected: selectedCategory == nil,
                                onTap: { selectedCategory = nil }
                            )
                            ForEach(AnnotationCategory.allCases, id: \.self) { cat in
                                CategoryChip(
                                    category: cat,
                                    isSelected: selectedCategory == cat,
                                    onTap: { selectedCategory = cat }
                                )
                            }
                        }
                    }
                }

                // Quick cue suggestions
                if !quickCues.isEmpty {
                    Section("Quick Cues") {
                        FlowLayout(spacing: 6) {
                            ForEach(quickCues.prefix(8)) { cue in
                                Button {
                                    noteText = cue.text
                                    selectedCategory = cue.annotationCategory
                                    Haptics.selection()
                                } label: {
                                    Text(cue.text)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(noteText == cue.text ? Color.green.opacity(0.2) : Color(.systemGray5))
                                        .foregroundColor(noteText == cue.text ? .green : .primary)
                                        .cornerRadius(16)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Note text
                Section("Note") {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 100)
                        .focused($isTextEditorFocused)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            isSaving = true
                            isTextEditorFocused = false
                            onSave(noteText.trimmingCharacters(in: .whitespacesAndNewlines), timestamp, selectedCategory)
                            dismiss()
                        }
                        .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isTextEditorFocused = false }
                }
            }
        }
    }

}

// MARK: - Category Chip

struct CategoryChip: View {
    let category: AnnotationCategory?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if let category {
                    Image(systemName: category.icon)
                        .font(.caption2)
                }
                Text(category?.displayName ?? "General")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? categoryColor.opacity(0.2) : Color(.systemGray5))
            .foregroundColor(isSelected ? categoryColor : .primary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? categoryColor : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var categoryColor: Color {
        category?.color ?? .secondary
    }
}
