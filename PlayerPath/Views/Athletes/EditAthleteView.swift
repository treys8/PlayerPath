//
//  EditAthleteView.swift
//  PlayerPath
//
//  Edits a single athlete's settings. Currently exposes the stat-tracking
//  toggle. Callers provide the NavigationStack — presented as a sheet from
//  AthleteProfileRow's info button and the Stats tab banner, and pushed from
//  the Profile tab's "Athlete Settings" link.
//

import SwiftUI
import SwiftData

struct EditAthleteView: View {
    @Bindable var athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccent) private var ppAccent
    @State private var showingAddSportProfile = false
    @State private var showingSplit = false

    /// Sports this athlete tracks — distinct seasons' sports, falling back to
    /// the athlete's primary-sport hint. Mirrors AthleteCard.athleteSports.
    private var currentSports: [Season.SportType] {
        let set = Set((athlete.seasons ?? []).map { $0.sport ?? .baseball })
        let sorted = set.sorted { $0.rawValue < $1.rawValue }
        if !sorted.isEmpty { return sorted }
        if let hint = Season.SportType(rawValue: (athlete.sport ?? .baseball).rawValue.capitalized) {
            return [hint]
        }
        return [.baseball]
    }

    var body: some View {
        Form {
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
                Text("Each profile tracks one sport. Adding a sport creates a separate linked profile — it shares your subscription slot, with its own seasons and stats.")
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

            Section {
                Toggle("Track Statistics", isOn: $athlete.trackStatsEnabled)
            } header: {
                Text("Statistics")
            } footer: {
                Text("When off, new recordings save without play-result tagging and won't add to stats. Existing stats stay visible and resume updating if you turn tracking back on.")
            }
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
            if athlete.needsSync, let user = athlete.user {
                Task { try? await SyncCoordinator.shared.syncAthletes(for: user) }
            }
        }
        .toolbar {
            // Done serves as the explicit dismiss control in sheet
            // presentations. In push context the back arrow handles it;
            // the extra button is harmless but visible.
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
