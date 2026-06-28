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
    @State private var endDate = Date()
    @State private var hasEndDate = false
    @State private var selectedSport: Season.SportType
    @State private var makeActive = true
    @State private var selectedSeasonType: Season.SeasonType? = nil
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isCreating = false

    init(athlete: Athlete, initialSport: Season.SportType? = nil) {
        self.athlete = athlete
        // Seasons are locked to the profile's own sport. Tracking another sport
        // means a separate linked profile (AddSportProfileSheet), not a
        // cross-sport season on this row. initialSport is retained only as an
        // explicit override and is normally nil.
        _selectedSport = State(initialValue: initialSport ?? athlete.sportType)
    }

    private var isCreatingPastSeason: Bool {
        !makeActive && athlete.activeSeason != nil
    }

    /// Sport-resolved accent — seasons are locked to the profile's own sport.
    private var accent: Color { Theme.accent(forGolf: selectedSport == .golf) }

    // Season name suggestions
    private var suggestedSeasons: [String] {
        let year = Calendar.current.component(.year, from: startDate)
        let month = Calendar.current.component(.month, from: startDate)

        var base: [String]
        if month >= 2 && month <= 6 {
            base = ["Spring \(year)", "Spring Season", "\(year) Season"]
        } else if month >= 7 && month <= 10 {
            base = ["Fall \(year)", "Fall Season", "\(year) Season"]
        } else {
            base = ["Winter \(year)", "\(year) Season", "Off-Season"]
        }
        // Lead with a type-specific suggestion when a category is chosen
        // (e.g. "Travel 2026"), de-duped against the season-based list.
        if let type = selectedSeasonType {
            let typed = "\(type.displayName) \(year)"
            base.removeAll { $0 == typed }
            base.insert(typed, at: 0)
        }
        return base
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
                                .font(.bodySmall)
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(suggestedSeasons, id: \.self) { suggestion in
                                        Button {
                                            seasonName = suggestion
                                        } label: {
                                            Text(suggestion)
                                                .font(.bodyMedium)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(accent.opacity(0.1))
                                                .foregroundColor(accent)
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

                    if isCreatingPastSeason {
                        Toggle("Set End Date", isOn: $hasEndDate.animation())
                        if hasEndDate {
                            DatePicker(
                                "End Date",
                                selection: $endDate,
                                in: startDate...Date(),
                                displayedComponents: .date
                            )
                        }
                    }
                } header: {
                    Text(isCreatingPastSeason ? "Season Dates" : "When does this season start?")
                } footer: {
                    if isCreatingPastSeason {
                        Text("Setting an end date helps us route past games and imported videos to the correct season.")
                    }
                }

                Section {
                    HStack {
                        Label(selectedSport.displayName, systemImage: selectedSport.icon)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Sport")
                } footer: {
                    Text("Seasons use this profile's sport. To track another sport, add a sport profile from the athlete's settings.")
                }

                Section {
                    Picker("Type", selection: $selectedSeasonType) {
                        Text("None").tag(Season.SeasonType?.none)
                        ForEach(Season.SeasonType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(Season.SeasonType?.some(type))
                        }
                    }
                } header: {
                    Text("Type (Optional)")
                } footer: {
                    Text("Categorize this season — helps organize seasons and adds context to a recruiting profile.")
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
        // Season.activate() now updates athlete.sport — capture so we can revert on save failure.
        let previousAthleteSport = athlete.sport

        // If making this active, archive the current active season
        if makeActive {
            previousActive?.archive()
        }

        // Create new season
        let newSeason = Season(name: seasonName.trimmingCharacters(in: .whitespacesAndNewlines),
                              startDate: startDate,
                              sport: selectedSport)
        newSeason.seasonType = selectedSeasonType?.rawValue

        if makeActive {
            newSeason.activate()
        } else if hasEndDate {
            // Past season: stamp an explicit end date so the interval has a precise
            // upper bound. (Without one, season(containing:) bounds the season at
            // end-of-today — past-dated imports still route correctly — but an explicit
            // end keeps the interval exact and prevents today's content from matching.)
            // Normalize to end-of-day so same-day games/videos aren't excluded.
            newSeason.endDate = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
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
                // Revert the athlete.sport mutation that activate() applied.
                athlete.sport = previousAthleteSport

                errorMessage = "Failed to create season: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}
