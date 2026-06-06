//
//  SeasonRecommendationBanner.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import SwiftUI
import SwiftData

/// A banner that shows season recommendations or warnings
struct SeasonRecommendationBanner: View {
    let athlete: Athlete
    let recommendation: SeasonManager.SeasonRecommendation
    private var activeSport: Season.SportType { athlete.sportType }
    @State private var showingSeasons = false
    @State private var dismissed = false

    /// Re-show a dismissed banner after this many seconds. The banner type encodes
    /// season-specific state (`considerEnding_<uuid>`), so the same season won't
    /// reappear before the window — but if the season hits a fresh threshold
    /// (e.g. growing past 12 months while the 6-month banner sits dismissed),
    /// the user gets nudged again.
    private static let reShowAfter: TimeInterval = 30 * 24 * 60 * 60

    private var dismissedKey: String {
        let recType: String
        switch recommendation {
        case .createFirst:     recType = "createFirst"
        case .noActiveSeason:  recType = "noActiveSeason"
        case .considerEnding(let season): recType = "considerEnding_\(season.id.uuidString)"
        case .ok:              recType = "ok"
        }
        // New key prefix so legacy Bool dismissals expire naturally.
        return "seasonBanner_dismissedAt_\(athlete.id.uuidString)_\(recType)"
    }

    private var isCurrentlyDismissed: Bool {
        let ts = UserDefaults.standard.double(forKey: dismissedKey)
        guard ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts < Self.reShowAfter
    }

    private var displayedMessage: String? {
        switch recommendation {
        case .createFirst where activeSport == .golf:
            return "Create your first season to start tracking tournaments and videos"
        case .noActiveSeason:
            // Sport-scope the copy: the check is filtered to the current sport
            // (checkSeasonStatus(for:sport:)), so a globally-worded "No active
            // season" reads as wrong when another sport's season is active.
            return "No active \(activeSport.displayName.lowercased()) season. Create a new season or reactivate an old one"
        default:
            return recommendation.message
        }
    }

    var body: some View {
        if !dismissed && !isCurrentlyDismissed, let message = displayedMessage {
            HStack(spacing: 12) {
                Image(systemName: iconForRecommendation)
                    .font(.title3)
                    .foregroundStyle(colorForRecommendation)

                VStack(alignment: .leading, spacing: 4) {
                    Text(titleForRecommendation)
                        .font(.headingSmall)

                    Text(message)
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingSeasons = true
                } label: {
                    Text("Manage")
                        .font(.custom("Inter18pt-SemiBold", size: 12, relativeTo: .caption))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(colorForRecommendation.opacity(0.2))
                        .foregroundStyle(colorForRecommendation)
                        .clipShape(Capsule())
                }

                Button {
                    withAnimation {
                        dismissed = true
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: dismissedKey)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorForRecommendation.opacity(0.1))
            }
            .sheet(isPresented: $showingSeasons) {
                NavigationStack {
                    SeasonsView(athlete: athlete)
                }
            }
        }
    }

    private var iconForRecommendation: String {
        switch recommendation {
        case .createFirst, .noActiveSeason:
            return "calendar.badge.plus"
        case .considerEnding:
            return "calendar.badge.exclamationmark"
        case .ok:
            return "checkmark.circle"
        }
    }

    private var colorForRecommendation: Color {
        switch recommendation {
        case .createFirst, .noActiveSeason:
            return Theme.accent(forGolf: activeSport == .golf)
        case .considerEnding:
            return Theme.warning
        case .ok:
            return .green
        }
    }

    private var titleForRecommendation: String {
        switch recommendation {
        case .createFirst:
            return "Get Started"
        case .noActiveSeason:
            return "Season Needed"
        case .considerEnding:
            return "Season Check"
        case .ok:
            return "All Set"
        }
    }
}

// MARK: - Preview

#Preview("Season Recommendation Banner") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    guard let container = try? ModelContainer(for: Athlete.self, Season.self, configurations: config) else {
        return VStack { Text("Preview unavailable") }
    }

    let athlete = Athlete(name: "Test Player")
    container.mainContext.insert(athlete)

    return VStack {
        SeasonRecommendationBanner(
            athlete: athlete,
            recommendation: .createFirst
        )
        .padding()

        SeasonRecommendationBanner(
            athlete: athlete,
            recommendation: .noActiveSeason
        )
        .padding()
    }
    .modelContainer(container)
}
