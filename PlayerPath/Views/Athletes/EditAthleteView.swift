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

    var body: some View {
        Form {
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
