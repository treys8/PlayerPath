//
//  AthleteCard.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData

struct AthleteCard: View {
    let athlete: Athlete
    let action: () -> Void
    /// Optional spin-off action — when set, a "Add Another Sport" item appears
    /// in the card's context menu, scoped to this athlete. The presenter owns
    /// the sheet so it can react to the resulting athlete switch.
    var onAddSport: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var isEndingGame = false

    /// The currently live game for this athlete, if any.
    private var liveGame: Game? {
        (athlete.games ?? []).first(where: { $0.isLive })
    }

    /// The athlete's pinned primary sport — the single source of truth for the
    /// card icon, matching the switcher (`PPAthleteSwitcher`) and the tab chrome
    /// (`MainTabView`). An athlete may have seasons in other sports, but the card
    /// reflects the one pinned sport, not every season's sport.
    private var sport: Sport { athlete.sport ?? .baseball }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                // Profile icon with background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.brandNavy.opacity(0.8), Color.brandNavy],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                }

                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: sport.icon)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)

                        Text(athlete.name)
                            .font(.headingLarge)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)
                    }

                    if let created = athlete.createdAt {
                        Text("Created \(created, format: .dateTime.day().month().year())")
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Created —")
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                    }
                }

                // Quick stats if available
                HStack(spacing: 16) {
                    AthleteStatBadge(
                        icon: "video",
                        count: (athlete.videoClips ?? []).count,
                        label: "Videos"
                    )

                    AthleteStatBadge(
                        icon: sport == .golf ? "figure.golf" : "baseball.diamond.bases",
                        count: (athlete.games ?? []).count,
                        label: sport == .golf ? "Rounds" : "Games"
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .appCard(cornerRadius: .cornerXLarge)
            .contextMenu {
                Button {
                    action()
                } label: {
                    Label("Open", systemImage: "arrow.right.circle")
                }
                if let liveGame = liveGame {
                    Button {
                        guard !isEndingGame else { return }
                        isEndingGame = true
                        Task {
                            await GameService(modelContext: modelContext).end(liveGame)
                            await MainActor.run { isEndingGame = false }
                        }
                    } label: {
                        Label(isEndingGame ? "Ending..." : "End Live", systemImage: "stop.circle")
                    }
                    .disabled(isEndingGame)
                }
                if let onAddSport {
                    Button {
                        onAddSport()
                    } label: {
                        Label("Add Another Sport", systemImage: "plus.circle")
                    }
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Select athlete \(athlete.name)")
        .accessibilityHint("Opens this athlete's dashboard")
    }
}
