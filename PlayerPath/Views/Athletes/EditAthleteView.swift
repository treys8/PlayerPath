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
    @State private var showingCreateSeason = false

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

    /// First sport in `Season.SportType.allCases` the athlete doesn't yet have
    /// — pre-selects the sport picker in CreateSeasonView from "Add a sport".
    /// nil when the athlete already plays every supported sport.
    private var nextMissingSport: Season.SportType? {
        let present = Set(currentSports)
        return Season.SportType.allCases.first { !present.contains($0) }
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
                            .background(Color.brandNavy.opacity(0.1))
                            .foregroundColor(.brandNavy)
                            .clipShape(Capsule())
                    }
                }
                Button {
                    showingCreateSeason = true
                } label: {
                    Label("Add a sport", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Sports")
            } footer: {
                Text("Each season belongs to one sport. Add a season in another sport to track that sport for this athlete.")
            }

            Section {
                Toggle("Track Statistics", isOn: $athlete.trackStatsEnabled)
            } header: {
                Text("Statistics")
            } footer: {
                Text("When off, new recordings save without play-result tagging and won't add to stats. Existing stats stay visible and resume updating if you turn tracking back on.")
            }
        }
        .navigationTitle(athlete.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCreateSeason) {
            CreateSeasonView(athlete: athlete, initialSport: nextMissingSport)
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
