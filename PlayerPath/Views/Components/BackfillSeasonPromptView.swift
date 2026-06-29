//
//  BackfillSeasonPromptView.swift
//  PlayerPath
//
//  Post-import correction prompt. Shown when a bulk import filed N items onto
//  the current season ONLY because their capture dates matched no existing
//  season (the silent-misfile case). Lets the user re-home those items to a
//  past season — created inline (pre-filled from the items' date range) or
//  chosen from existing seasons — or keep them on the current season.
//
//  Type-agnostic: the caller supplies an `onResolve` closure that performs the
//  actual re-routing (video vs photo), so this view owns no model writes beyond
//  inline season creation.
//

import SwiftUI

struct BackfillSeasonPromptView: View {
    let athlete: Athlete
    let unmatchedCount: Int
    let dateRange: ClosedRange<Date>
    let currentSeasonName: String
    /// Non-nil → move the unmatched items to this season; nil → keep on current.
    let onResolve: (Season?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showingCreate = false
    @State private var pickedSeason: Season?
    /// Stashed by the inline-create sheet so we resolve only AFTER that child
    /// sheet has fully dismissed (via its onDismiss) — dismissing this prompt
    /// while the child is still presenting would drop the dismissal.
    @State private var createdSeason: Season?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("^[\(unmatchedCount) item](inflect: true) older than \(currentSeasonName)")
                            .font(.headingMedium)
                        Text(rangeText)
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                        Text("These were filed on \(currentSeasonName) because their dates don't fall within any season. Where should they go?")
                            .font(.bodySmall)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        showingCreate = true
                    } label: {
                        Label("Create a Past Season", systemImage: "calendar.badge.plus")
                    }
                } footer: {
                    Text("Make a season for these older items. It's archived — your current season stays active.")
                }

                if !(athlete.seasons ?? []).isEmpty {
                    Section {
                        SeasonPickerRow(
                            athlete: athlete,
                            selection: $pickedSeason,
                            allowsNone: true,
                            noneLabel: "Choose a season…"
                        )
                        if let pickedSeason {
                            Button("Move to \(pickedSeason.displayName)") {
                                resolve(pickedSeason)
                            }
                        }
                    } header: {
                        Text("Move to an existing season").smallCapsLabel()
                    }
                }

                Section {
                    Button(role: .cancel) {
                        resolve(nil)
                    } label: {
                        Text("Keep on \(currentSeasonName)")
                    }
                }
            }
            .navigationTitle("Older Items Found")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .sheet(isPresented: $showingCreate, onDismiss: {
                if let season = createdSeason {
                    createdSeason = nil
                    resolve(season)
                }
            }) {
                CreatePastSeasonInlineSheet(
                    athlete: athlete,
                    draftRange: dateRange
                ) { newSeason in
                    // Stash + let the child dismiss itself; resolve() runs in
                    // the onDismiss above, after the child is gone.
                    createdSeason = newSeason
                }
            }
        }
    }

    private func resolve(_ season: Season?) {
        onResolve(season)
        dismiss()
    }

    private var rangeText: String {
        let f = DateFormatter.mediumDate
        let lo = f.string(from: dateRange.lowerBound)
        let hi = f.string(from: dateRange.upperBound)
        return lo == hi ? lo : "\(lo) – \(hi)"
    }
}

/// Minimal inline form for creating an archived past season from the backfill
/// prompt. Pre-fills name + dates from the imported batch's capture range via
/// `SeasonManager.draftPastSeason`. On success it creates the season, kicks off
/// a background season sync, and hands the new season back to the caller.
private struct CreatePastSeasonInlineSheet: View {
    let athlete: Athlete
    let draftRange: ClosedRange<Date>
    let onCreated: (Season) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Season Name", text: $name)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                } header: {
                    Text("Season Name")
                }

                Section {
                    // Bound to today so Start can never exceed End's upper bound
                    // (a startDate > Date() would make `startDate...Date()` an
                    // invalid range and trap on render).
                    DatePicker("Start", selection: $startDate, in: ...Date(), displayedComponents: .date)
                    DatePicker("End", selection: $endDate, in: startDate...Date(), displayedComponents: .date)
                } header: {
                    Text("Dates")
                } footer: {
                    Text("Covers the imported items' capture dates. Created as an archived season — your current season stays active.")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.bodySmall)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("New Past Season")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        create()
                    } label: {
                        if isCreating { ProgressView() } else { Text("Create") }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .onAppear {
                let draft = SeasonManager.draftPastSeason(
                    from: draftRange.lowerBound,
                    to: draftRange.upperBound,
                    for: athlete
                )
                name = draft.name
                startDate = draft.start
                endDate = draft.end
            }
        }
    }

    private func create() {
        isCreating = true
        let sport = athlete.sportType
        guard let season = SeasonManager.createPastSeason(
            name: name,
            startDate: startDate,
            endDate: endDate,
            sport: sport,
            for: athlete,
            in: modelContext
        ) else {
            isCreating = false
            errorMessage = "Couldn't create the season. Please try again."
            return
        }

        Haptics.medium()
        if let user = athlete.user {
            Task {
                do {
                    try await SyncCoordinator.shared.syncSeasons(for: user)
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "BackfillSeason.syncSeasons", showAlert: false)
                }
            }
        }
        onCreated(season)
        // Dismiss this child sheet first; the parent prompt resolves in its
        // .sheet onDismiss once we're fully gone (avoids a dismissal race).
        dismiss()
    }
}
