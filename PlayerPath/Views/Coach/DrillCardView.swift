//
//  DrillCardView.swift
//  PlayerPath
//
//  Full drill card editor: template picker, star ratings, notes, summary.
//

import SwiftUI

struct DrillCardView: View {
    let videoID: String
    let coachID: String
    let coachName: String
    var existingCard: DrillCard?
    let onSave: (DrillCard) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplate: DrillCardTemplate = .battingReview
    @State private var selectedSavedTemplateID: String?
    @State private var categories: [DrillCardCategory] = []
    @State private var overallRating: Int?
    @State private var summary = ""
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var showingSaveTemplateAlert = false
    @State private var newTemplateName = ""
    private let templateService = CoachTemplateService.shared

    private var templatePickerLabel: String {
        if let id = selectedSavedTemplateID,
           let saved = templateService.drillTemplates.first(where: { $0.id == id }) {
            return saved.name
        }
        return selectedTemplate.displayName
    }

    var body: some View {
        NavigationStack {
            Form {
                // Template picker
                if existingCard == nil {
                    Section("Template") {
                        Menu {
                            // Built-in templates
                            ForEach(DrillCardTemplate.allCases, id: \.self) { template in
                                Button(template.displayName) {
                                    applyBuiltInTemplate(template)
                                }
                            }
                            if !templateService.drillTemplates.isEmpty {
                                Divider()
                                ForEach(templateService.drillTemplates) { saved in
                                    Button(saved.name) {
                                        applySavedTemplate(saved)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Type")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(templatePickerLabel)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if !categories.isEmpty {
                            Button {
                                newTemplateName = templatePickerLabel
                                showingSaveTemplateAlert = true
                            } label: {
                                Label("Save as template…", systemImage: "square.and.arrow.down")
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                // Category ratings
                Section("Ratings") {
                    ForEach(categories.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(categories[index].name)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            StarRatingView(rating: $categories[index].rating)

                            TextField("Notes (optional)", text: Binding(
                                get: { categories[index].notes ?? "" },
                                set: { categories[index].notes = $0.isEmpty ? nil : $0 }
                            ))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Overall
                Section("Overall") {
                    HStack {
                        Text("Overall Rating")
                        Spacer()
                        StarRatingView(rating: Binding(
                            get: { overallRating ?? 0 },
                            set: { overallRating = $0 == 0 ? nil : $0 }
                        ))
                    }

                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(3...6)
                }

            }
            .navigationTitle(existingCard != nil ? "Edit Drill Card" : "New Drill Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(categories.isEmpty || isSaving)
                }
            }
            .alert("Unable to Save", isPresented: .init(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK") { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .alert("Save as Template", isPresented: $showingSaveTemplateAlert) {
                TextField("Template name", text: $newTemplateName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveAsTemplate() }
                    .disabled(newTemplateName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Saved templates appear in the Type menu next time you create a drill card.")
            }
            .onAppear {
                if let card = existingCard {
                    selectedTemplate = DrillCardTemplate(rawValue: card.templateType) ?? .custom
                    categories = card.categories
                    overallRating = card.overallRating
                    summary = card.summary ?? ""
                } else {
                    categories = selectedTemplate.defaultCategories.map {
                        DrillCardCategory(name: $0, rating: 3)
                    }
                }
            }
        }
    }

    private func applyBuiltInTemplate(_ template: DrillCardTemplate) {
        selectedTemplate = template
        selectedSavedTemplateID = nil
        categories = template.defaultCategories.map {
            DrillCardCategory(name: $0, rating: 3)
        }
    }

    private func applySavedTemplate(_ saved: SavedDrillTemplate) {
        selectedTemplate = DrillCardTemplate(rawValue: saved.templateType) ?? .custom
        selectedSavedTemplateID = saved.id
        categories = saved.categoryNames.map { DrillCardCategory(name: $0, rating: 3) }
        if let pref = saved.defaultSummary, summary.isEmpty {
            summary = pref
        }
        if let id = saved.id {
            Task { await templateService.incrementDrillTemplateUsage(coachID: coachID, templateID: id) }
        }
    }

    private func saveAsTemplate() {
        let trimmed = newTemplateName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !categories.isEmpty else { return }
        let names = categories.map(\.name)
        let pref: String? = summary.trimmingCharacters(in: .whitespaces).isEmpty ? nil : summary
        Task {
            do {
                _ = try await templateService.saveDrillTemplate(
                    coachID: coachID,
                    name: trimmed,
                    templateType: selectedTemplate.rawValue,
                    categoryNames: names,
                    defaultSummary: pref
                )
            } catch {
                ErrorHandlerService.shared.handle(error, context: "DrillCardView.saveAsTemplate", showAlert: false)
            }
        }
        newTemplateName = ""
    }

    private func save() {
        isSaving = true
        Task {
            do {
                if var card = existingCard, let cardID = card.id {
                    try await FirestoreManager.shared.updateDrillCard(
                        videoID: videoID,
                        cardID: cardID,
                        categories: categories,
                        overallRating: overallRating,
                        summary: summary.isEmpty ? nil : summary
                    )
                    card.categories = categories
                    card.overallRating = overallRating
                    card.summary = summary.isEmpty ? nil : summary
                    onSave(card)
                } else {
                    let card = try await FirestoreManager.shared.createDrillCard(
                        videoID: videoID,
                        coachID: coachID,
                        coachName: coachName,
                        templateType: selectedTemplate.rawValue,
                        categories: categories,
                        overallRating: overallRating,
                        summary: summary.isEmpty ? nil : summary
                    )
                    onSave(card)
                }
                await MainActor.run { dismiss() }
            } catch {
                ErrorHandlerService.shared.handle(error, context: "DrillCardView.save", showAlert: false)
                saveErrorMessage = "Couldn't save drill card: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}

// MARK: - Star Rating

struct StarRatingView: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.subheadline)
                    .foregroundColor(star <= rating ? .yellow : .gray.opacity(0.4))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        rating = star == rating ? 0 : star
                        Haptics.selection()
                    }
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue(star <= rating ? "selected" : "not selected")
            }
        }
    }
}
