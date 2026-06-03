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
    /// Pre-selected practice type when launched from NewPracticeTypePicker
    /// (golf) or another contextual path. Nil falls back to the sport-default.
    var initialType: PracticeType? = nil
    var onCreated: ((Practice) -> Void)? = nil

    @State private var practiceType: PracticeType = .general
    @State private var date: Date = Date()
    @State private var selectedSeason: Season?
    @State private var holes: Int = 18
    @State private var course: String = ""
    @State private var didInit = false
    @State private var showingValidationError = false
    @State private var validationMessage = ""
    /// Golf single-live confirmation — shown when this new practice would go
    /// live but another golf activity already is.
    @State private var showingSingleLiveConfirm = false

    private var hasMultipleSeasons: Bool {
        (athlete.seasons?.count ?? 0) > 1
    }

    private var availableTypes: [PracticeType] {
        PracticeType.cases(for: athlete.sportType)
    }

    private var defaultTypeForSport: PracticeType {
        athlete.sportType == .golf ? .practiceRound : .general
    }

    private var isGolf: Bool { athlete.sportType == .golf }

    /// The season this practice will land on for the live-eligibility check.
    private var effectiveSeason: Season? {
        selectedSeason ?? athlete.activeSeason
    }

    /// Golf practices go live immediately when created for today on an active
    /// season — no separate toggle. Backdated/future practices, inactive
    /// seasons, and all baseball practices stay historical logs.
    private var shouldGoLive: Bool {
        isGolf
            && Calendar.current.isDateInToday(date)
            && (effectiveSeason?.isActive ?? true)
    }

    private var courseFieldLabel: String {
        practiceType == .rangeSession ? "Location" : "Course"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Details").smallCapsLabel()) {
                    Picker("Type", selection: $practiceType) {
                        ForEach(availableTypes) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type)
                        }
                    }
                    DatePicker("Date", selection: $date)

                    // Hole count picker — only shown for golf practice rounds.
                    // Range sessions and baseball practices stay holes=nil.
                    if practiceType == .practiceRound {
                        Picker("Holes", selection: $holes) {
                            Text("9").tag(9)
                            Text("18").tag(18)
                        }
                        .pickerStyle(.segmented)
                    }

                    // Optional course / location for golf — surfaced as the
                    // live card subtitle. Baseball practices skip it.
                    if isGolf {
                        TextField(courseFieldLabel, text: $course)
                            .textInputAutocapitalization(.words)
                    }
                }

                if hasMultipleSeasons {
                    Section {
                        SeasonPickerRow(athlete: athlete, selection: $selectedSeason)
                    } header: {
                        Text("Season").smallCapsLabel()
                    } footer: {
                        if let selectedSeason, !selectedSeason.isActive {
                            Text("This practice will be filed on a past season.")
                        }
                    }
                }
            }
            .ppDetailBackground()
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
                guard !didInit else { return }
                selectedSeason = athlete.activeSeason
                practiceType = initialType ?? defaultTypeForSport
                didInit = true
            }
            .alert("Validation Error", isPresented: $showingValidationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
            .confirmationDialog(
                "End your live \(LiveActivityGuard.currentLiveGolfLabel(for: athlete) ?? "activity")?",
                isPresented: $showingSingleLiveConfirm,
                titleVisibility: .visible
            ) {
                Button("End & Start New", role: .destructive) { performCreate() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You already have a live \(LiveActivityGuard.currentLiveGolfLabel(for: athlete) ?? "activity") going. Starting a new one will end it.")
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

        // Golf single-live guard: if this practice would go live and another
        // golf activity already is, confirm the replacement first. Otherwise
        // create straight away.
        if shouldGoLive && LiveActivityGuard.hasAnyLiveGolf(for: athlete) {
            showingSingleLiveConfirm = true
            return
        }

        performCreate()
    }

    private func performCreate() {
        let practice = Practice(date: date)
        practice.practiceType = practiceType.rawValue
        // Persist hole count only for golf practice rounds; range sessions
        // and baseball practices stay nil so LiveHoleTracker's gate is clean.
        practice.holes = (practiceType == .practiceRound) ? holes : nil
        let trimmedCourse = course.trimmingCharacters(in: .whitespacesAndNewlines)
        practice.course = (isGolf && !trimmedCourse.isEmpty) ? trimmedCourse : nil
        practice.athlete = athlete
        practice.needsSync = true

        // Go live inline (mirrors GameService.createGame). Ending any other
        // live golf activity here enforces the single-live invariant even if
        // the confirmation was skipped (nothing was live at save time).
        if shouldGoLive {
            PracticeService.endAllOtherLiveGolf(for: athlete, exceptPractice: practice)
            practice.isLive = true
            practice.liveStartDate = Date()
        }

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
