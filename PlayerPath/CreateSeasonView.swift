//
//  CreateSeasonView.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import SwiftUI
import SwiftData

struct CreateSeasonView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var seasonName = ""
    @State private var startDate = Date()
    @State private var selectedSport: Season.SportType = .baseball
    @State private var makeActive = true
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isCreating = false

    // Season name suggestions
    private var suggestedSeasons: [String] {
        let year = Calendar.current.component(.year, from: startDate)
        let month = Calendar.current.component(.month, from: startDate)

        if month >= 2 && month <= 6 {
            return ["Spring \(year)", "Spring Season", "\(year) Season"]
        } else if month >= 7 && month <= 10 {
            return ["Fall \(year)", "Fall Season", "\(year) Season"]
        } else {
            return ["Winter \(year)", "\(year) Season", "Off-Season"]
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Season Name", text: $seasonName)
                        .autocorrectionDisabled()
                        .submitLabel(.done)

                    // Quick suggestions
                    if seasonName.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggestions:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(suggestedSeasons, id: \.self) { suggestion in
                                        Button {
                                            seasonName = suggestion
                                        } label: {
                                            Text(suggestion)
                                                .font(.subheadline)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.brandNavy.opacity(0.1))
                                                .foregroundColor(.brandNavy)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Season Information")
                } footer: {
                    Text("Give this season a name like 'Spring 2025' or 'Fall League'")
                }

                Section {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                } header: {
                    Text("When does this season start?")
                }

                Section {
                    Picker("Sport", selection: $selectedSport) {
                        ForEach(Season.SportType.allCases, id: \.self) { sport in
                            Label(sport.displayName, systemImage: sport.icon)
                                .tag(sport)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Sport")
                }

                if athlete.activeSeason != nil {
                    Section {
                        Toggle("Make this the active season", isOn: $makeActive)
                    } footer: {
                        Text("If enabled, this will end the current active season and make this one active. Otherwise, it will be created as an archived season.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Season")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createSeason()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(seasonName.isEmpty || isCreating)
                }
            }
            .alert("Unable to Create Season", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func createSeason() {
        // Validate
        guard !seasonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a season name"
            showingError = true
            return
        }

        // Capture before any mutations so rollback has the correct reference
        let previousActive = athlete.activeSeason
        let previousActiveWasActive = previousActive?.isActive ?? false
        let previousActiveEndDate = previousActive?.endDate

        // If making this active, archive the current active season
        if makeActive {
            previousActive?.archive()
        }

        // Create new season
        let newSeason = Season(name: seasonName.trimmingCharacters(in: .whitespacesAndNewlines),
                              startDate: startDate,
                              sport: selectedSport)

        if makeActive {
            newSeason.activate()
        }

        // Link to athlete
        newSeason.athlete = athlete
        athlete.seasons = athlete.seasons ?? []
        athlete.seasons?.append(newSeason)

        // Mark for Firestore sync (Phase 2)
        newSeason.needsSync = true

        // Insert and save
        modelContext.insert(newSeason)

        isCreating = true
        Task {
            do {
                try modelContext.save()

                // Track season creation analytics
                AnalyticsService.shared.trackSeasonCreated(
                    seasonID: newSeason.id.uuidString,
                    sport: selectedSport.rawValue,
                    isActive: makeActive
                )

                // Track season activation if making active
                if makeActive {
                    AnalyticsService.shared.trackSeasonActivated(seasonID: newSeason.id.uuidString)
                }

                // Success — dismiss immediately, sync in background
                Haptics.medium()
                dismiss()

                // Fire-and-forget sync — view is already dismissed
                if let user = athlete.user {
                    do {
                        try await SyncCoordinator.shared.syncSeasons(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "SeasonManagement.syncSeasons", showAlert: false)
                    }
                }
            } catch {
                // Rollback on failure
                isCreating = false
                modelContext.delete(newSeason)
                athlete.seasons?.removeAll { $0.id == newSeason.id }

                if previousActiveWasActive {
                    previousActive?.activate()
                    previousActive?.endDate = previousActiveEndDate
                }

                errorMessage = "Failed to create season: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}
