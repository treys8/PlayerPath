//
//  SeasonStartDecision.swift
//  PlayerPath
//
//  Shared "no active season" decision for the game-creation flows. Ended seasons
//  are read-only, so when a user adds a game with no active season we prompt them
//  to reactivate their last ended season (of the current sport) or start a new
//  one — never silently mint a phantom "today" season. Used by GameCreationView
//  and AddGameView.
//

import SwiftUI
import SwiftData

extension Athlete {
    /// Most recent ended (archived) season of the given sport — the reactivate
    /// candidate when adding a game with no active season. `archivedSeasons` is
    /// already newest-first; we filter to the active sport so a two-sport /
    /// mixed-history athlete doesn't reactivate the wrong sport's season.
    func mostRecentEndedSeason(ofSport sport: Season.SportType) -> Season? {
        archivedSeasons.first { ($0.sport ?? .baseball) == sport }
    }
}

extension View {
    /// Presents the "No Active Season" decision. Once a concrete active season
    /// exists (reactivated or newly started), `onResolved(season)` fires so the
    /// caller can proceed with game creation. `onCancel` fires if the user backs
    /// out or the operation fails.
    func seasonStartDecision(
        isPresented: Binding<Bool>,
        athlete: Athlete?,
        sport: Season.SportType,
        modelContext: ModelContext,
        onCancel: @escaping () -> Void = {},
        onResolved: @escaping (Season) -> Void
    ) -> some View {
        modifier(SeasonStartDecisionModifier(
            isPresented: isPresented,
            athlete: athlete,
            sport: sport,
            modelContext: modelContext,
            onCancel: onCancel,
            onResolved: onResolved
        ))
    }
}

private struct SeasonStartDecisionModifier: ViewModifier {
    @Binding var isPresented: Bool
    let athlete: Athlete?
    let sport: Season.SportType
    let modelContext: ModelContext
    let onCancel: () -> Void
    let onResolved: (Season) -> Void

    private var candidate: Season? { athlete?.mostRecentEndedSeason(ofSport: sport) }

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "No Active Season",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            if let candidate {
                Button("Reactivate \(candidate.displayName)") {
                    reactivate(candidate)
                }
            }
            Button("Start New Season") { startNew() }
            Button("Cancel", role: .cancel) { onCancel() }
        } message: {
            if let candidate {
                Text("Ended seasons are read-only. Reactivate \(candidate.displayName) to add this game — you can end it again later — or start a new season.")
            } else {
                Text("You don't have an active season. Start a new one to add this game.")
            }
        }
    }

    private func reactivate(_ season: Season) {
        guard let athlete else { onCancel(); return }
        Task { @MainActor in
            do {
                try await SeasonService.reactivateSeason(season, athlete: athlete, modelContext: modelContext)
                onResolved(season)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "SeasonStartDecision.reactivate", showAlert: true)
                onCancel()
            }
        }
    }

    private func startNew() {
        guard let athlete else { onCancel(); return }
        if let newSeason = SeasonManager.ensureActiveSeason(for: athlete, in: modelContext) {
            onResolved(newSeason)
        } else {
            onCancel()
        }
    }
}
