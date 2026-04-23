//
//  AddPracticeView.swift
//  PlayerPath
//
//  Full practice creation sheet with type, date, and season selection.
//  The quick-create menu path in PracticesView covers the "log one right now
//  on the active season" case; this sheet is for scheduling a practice or
//  filing one onto a past season.
//

import SwiftUI
import SwiftData
import os

private let addPracticeLog = Logger(subsystem: "com.playerpath.app", category: "AddPracticeView")

struct AddPracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let athlete: Athlete
    var onCreated: ((Practice) -> Void)? = nil

    @State private var practiceType: PracticeType = .general
    @State private var date: Date = Date()
    @State private var selectedSeason: Season?
    @State private var didInitSeason = false
    @State private var showingValidationError = false
    @State private var validationMessage = ""

    private var hasMultipleSeasons: Bool {
        (athlete.seasons?.count ?? 0) > 1
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    Picker("Type", selection: $practiceType) {
                        ForEach(PracticeType.allCases) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type)
                        }
                    }
                    DatePicker("Date", selection: $date)
                }

                if hasMultipleSeasons {
                    Section {
                        SeasonPickerRow(athlete: athlete, selection: $selectedSeason)
                    } header: {
                        Text("Season")
                    } footer: {
                        if let selectedSeason, !selectedSeason.isActive {
                            Text("This practice will be filed on a past season.")
                        }
                    }
                }
            }
            .navigationTitle("New Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                guard !didInitSeason else { return }
                selectedSeason = athlete.activeSeason
                didInitSeason = true
            }
            .alert("Validation Error", isPresented: $showingValidationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
        }
    }

    private func save() {
        // Bound the practice date by the selected season when one is chosen.
        if let selectedSeason {
            let start = selectedSeason.startDate ?? .distantPast
            let end = selectedSeason.endDate ?? .distantFuture
            if date < start {
                validationMessage = "Practice date is before the selected season starts."
                showingValidationError = true
                return
            }
            if date > end {
                validationMessage = "Practice date is after the selected season ends."
                showingValidationError = true
                return
            }
        }

        let practice = Practice(date: date)
        practice.practiceType = practiceType.rawValue
        practice.athlete = athlete
        practice.needsSync = true

        if athlete.practices == nil { athlete.practices = [] }
        athlete.practices?.append(practice)
        modelContext.insert(practice)

        // Assigning season upstream — linkPracticeToActiveSeason is a no-op when
        // practice.season is already set (SeasonManager.swift:77), so it's safe
        // to call as a fallback for users who leave the picker on "none".
        practice.season = selectedSeason
        if practice.season == nil {
            SeasonManager.linkPracticeToActiveSeason(practice, for: athlete, in: modelContext)
        }

        let saved = ErrorHandlerService.shared.saveContext(modelContext, caller: "AddPracticeView.save")
        guard saved else {
            Haptics.error()
            return
        }

        AnalyticsService.shared.trackPracticeCreated(
            practiceID: practice.id.uuidString,
            seasonID: practice.season?.id.uuidString
        )

        if let user = athlete.user {
            Task {
                do {
                    try await SyncCoordinator.shared.syncPractices(for: user)
                } catch {
                    addPracticeLog.error("Failed to sync practice to Firestore: \(error.localizedDescription)")
                }
            }
        }

        Haptics.success()
        onCreated?(practice)
        dismiss()
    }
}
