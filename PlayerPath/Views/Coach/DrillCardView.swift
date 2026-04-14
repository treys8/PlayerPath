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
    @State private var categories: [DrillCardCategory] = []
    @State private var overallRating: Int?
    @State private var summary = ""
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                // Template picker
                if existingCard == nil {
                    Section("Template") {
                        Picker("Type", selection: $selectedTemplate) {
                            ForEach(DrillCardTemplate.allCases, id: \.self) { template in
                                Text(template.displayName).tag(template)
                            }
                        }
                        .onChange(of: selectedTemplate) { _, template in
                            categories = template.defaultCategories.map {
                                DrillCardCategory(name: $0, rating: 3)
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
