//
//  QuickCueManager.swift
//  PlayerPath
//
//  Sheet for managing custom quick cues (add, delete).
//

import SwiftUI

struct QuickCueManager: View {
    let coachID: String
    @ObservedObject private var templateService = CoachTemplateService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newCueText = ""
    @State private var newCueCategory: AnnotationCategory = .positive

    var body: some View {
        NavigationStack {
            List {
                // Add new cue
                Section("Add Quick Cue") {
                    TextField("Cue text (e.g., 'Stay back')", text: $newCueText)
                        .submitLabel(.done)
                        .onSubmit { addCue() }

                    Picker("Category", selection: $newCueCategory) {
                        ForEach(AnnotationCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }

                    Button {
                        addCue()
                    } label: {
                        Label("Add Cue", systemImage: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                    .disabled(newCueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Existing cues
                if !templateService.quickCues.isEmpty {
                    Section("Your Quick Cues") {
                        ForEach(templateService.quickCues) { cue in
                            HStack {
                                if let cat = cue.annotationCategory {
                                    Circle()
                                        .fill(cat.color)
                                        .frame(width: 8, height: 8)
                                }
                                Text(cue.text)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(cue.usageCount)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    let cue = templateService.quickCues[index]
                                    guard let cueID = cue.id else { continue }
                                    try? await templateService.deleteQuickCue(coachID: coachID, cueID: cueID)
                                }
                            }
                        }
                    }
                }

                // Seed defaults
                if templateService.quickCues.isEmpty {
                    Section {
                        Button {
                            Task { await templateService.seedDefaultCues(coachID: coachID) }
                        } label: {
                            Label("Load Default Cues", systemImage: "wand.and.stars")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .navigationTitle("Quick Cues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addCue() {
        let text = newCueText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            _ = try? await templateService.addQuickCue(coachID: coachID, text: text, category: newCueCategory)
            newCueText = ""
            Haptics.success()
        }
    }
}
