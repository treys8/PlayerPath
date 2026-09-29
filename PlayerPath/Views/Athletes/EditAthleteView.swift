//
//  EditAthleteView.swift
//  PlayerPath
//
//  Edits a single athlete's settings — name, sports, recruiting, stat tracking.
//  Callers provide the NavigationStack — presented as a sheet from
//  AthleteProfileRow's info button and the Stats tab banner, and pushed from
//  the Profile tab's "Athlete Settings" link (which passes
//  `showsDoneButton: false` — the back arrow is the exit there).
//

import SwiftUI
import SwiftData

struct EditAthleteView: View {
    @Bindable var athlete: Athlete
    /// Sheet presentations need Done; pushed ones already have a back arrow.
    var showsDoneButton: Bool = true
    /// When set, shows "Delete Athlete". The view only reports the confirmed
    /// intent and dismisses — the presenter deletes after the sheet is gone,
    /// so this view never renders a deleted @Model.
    var onDeleteRequested: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccent) private var ppAccent
    @State private var showingAddSportProfile = false
    @State private var showingSplit = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false

    private var currentSports: [Season.SportType] { athlete.trackedSports }

    var body: some View {
        Form {
            AthleteNameSection(athlete: athlete)

            Section {
                HStack(spacing: 8) {
                    ForEach(currentSports, id: \.self) { sport in
                        Label(sport.displayName, systemImage: sport.icon)
                            .font(.bodyMedium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.accent(forGolf: sport == .golf).opacity(0.1))
                            .foregroundColor(Theme.accent(forGolf: sport == .golf))
                            .clipShape(Capsule())
                    }
                }
                if athlete.canAddSportProfile {
                    Button {
                        showingAddSportProfile = true
                    } label: {
                        Label("Add a sport", systemImage: "plus.circle.fill")
                    }
                }
            } header: {
                Text("Sports")
            } footer: {
                Text("Each sport gets its own linked profile with separate seasons and stats — it doesn't use another athlete slot.")
            }

            if athlete.isLegacySplittable {
                Section {
                    Button {
                        showingSplit = true
                    } label: {
                        Label("Split into separate profiles", systemImage: "rectangle.split.2x1")
                    }
                } header: {
                    Text("Multiple Sports")
                } footer: {
                    Text("This profile tracks more than one sport on one row. Split it so each sport gets its own linked profile — overlapping seasons, separate stats, same subscription slot.")
                }
            }

            // The per-athlete home for recruiting. The Profile-tab row keys off
            // whichever athlete is selected and reads as account-level; in here
            // there's no ambiguity about whose photo and contact info goes public.
            if RecruitingFeature.isEnabled {
                Section {
                    NavigationLink {
                        // `.id` for the same reason as the Profile-tab route: the
                        // editor holds the bio in @State, so it must be recreated
                        // rather than re-rendered if the athlete underneath changes.
                        RecruitingProfileEditorView(athlete: athlete)
                            .id(athlete.id)
                    } label: {
                        Label("Recruiting Profile", systemImage: "graduationcap.fill")
                    }
                } header: {
                    Text("Recruiting")
                } footer: {
                    Text("Build a profile page you can send to college coaches — film first, plus measurables and contact info you choose to share.")
                }
            }

            Section {
                Toggle("Track Statistics", isOn: $athlete.trackStatsEnabled)
            } header: {
                Text("Statistics")
            } footer: {
                if athlete.sportType == .golf {
                    Text("When off, new recordings save without shot tagging. Your scorecards aren't affected.")
                } else {
                    Text("When off, new recordings save without play-result tagging and won't add to stats. Existing stats stay visible and resume updating if you turn tracking back on.")
                }
            }

            if onDeleteRequested != nil {
                Section {
                    Button("Delete Athlete", role: .destructive) {
                        Haptics.warning()
                        showingDeleteConfirm = true
                    }
                }
            }
        }
        .confirmationDialog("Delete \(athlete.name)?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Haptics.heavy()
                isDeleting = true
                onDeleteRequested?()
                dismiss()
            }
        } message: {
            Text("This will delete the athlete and related data. This action cannot be undone.")
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle(athlete.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddSportProfile) {
            NavigationStack {
                AddSportProfileSheet(sourceAthlete: athlete)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSplit) {
            NavigationStack {
                SplitSportProfileSheet(athlete: athlete)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: athlete.trackStatsEnabled) { _, _ in
            // Mark dirty immediately so the change is captured regardless of
            // how the user exits (Done, back arrow, or swipe-dismiss).
            athlete.needsSync = true
        }
        .onDisappear {
            // Single exit path for persistence + sync. Fires for every way
            // the view can go away — matches iOS Settings-style "changes
            // apply immediately" behavior without depending on Done.
            ErrorHandlerService.shared.saveContext(modelContext, caller: "EditAthleteView.onDisappear")
            // A delete is about to run — syncing now would race it (touch the
            // deleted row, or re-upload the doc it tombstones).
            if !isDeleting, athlete.needsSync, let user = athlete.user {
                Task { try? await SyncCoordinator.shared.syncAthletes(for: user) }
            }
        }
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
