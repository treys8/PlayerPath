import SwiftUI
import SwiftData

struct DashboardNextStepCard: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    private var activeSport: Season.SportType { athlete.sportType }
    @State private var dismissedTipID: String?
    @Query private var prefs: [UserPreferences]

    private enum Step {
        case createGame
        case recordVideo

        var tipID: String {
            switch self {
            case .createGame: return "next_step_create_game"
            case .recordVideo: return "next_step_record_video"
            }
        }

        func icon(for sport: Season.SportType) -> String {
            switch self {
            case .createGame: return sport == .golf ? "figure.golf" : "baseball.diamond.bases"
            case .recordVideo: return "video.badge.plus"
            }
        }

        var color: Color {
            switch self {
            case .createGame: return .green
            case .recordVideo: return .purple
            }
        }

        func title(for sport: Season.SportType) -> String {
            switch self {
            case .createGame: return sport == .golf ? "Log Your First Round" : "Log Your First Game"
            case .recordVideo: return "Record Your First Video"
            }
        }

        func message(for sport: Season.SportType) -> String {
            switch self {
            case .createGame:
                return sport == .golf
                    ? "Start tracking your scores by logging a round"
                    : "Start tracking your at-bats and stats by creating a game"
            case .recordVideo: return "Record your swing to review your mechanics"
            }
        }

        func buttonLabel(for sport: Season.SportType) -> String {
            switch self {
            case .createGame: return sport == .golf ? "Tournaments" : "Games"
            case .recordVideo: return "Videos"
            }
        }

        var tab: MainTab {
            switch self {
            case .createGame: return .games
            case .recordVideo: return .videos
            }
        }
    }

    private var currentStep: Step? {
        guard prefs.first?.showOnboardingTips ?? true else { return nil }
        // Sport-scope the emptiness checks so a stale cross-sport game/clip
        // doesn't silently suppress the onboarding prompt for the active sport.
        // Same rule as GamesView.filterGames: season-sport match, seasonless
        // passes through.
        let activeSportGames = (athlete.games ?? []).filter { game in
            guard let seasonSport = game.season?.sport else { return true }
            return seasonSport == activeSport
        }
        let activeSportClips = (athlete.videoClips ?? []).filter { clip in
            guard let seasonSport = clip.season?.sport else { return true }
            return seasonSport == activeSport
        }
        if activeSportGames.isEmpty,
           OnboardingManager.shared.shouldShowTip(Step.createGame.tipID) {
            return .createGame
        }
        if activeSportClips.isEmpty,
           OnboardingManager.shared.shouldShowTip(Step.recordVideo.tipID) {
            return .recordVideo
        }
        return nil
    }

    var body: some View {
        cardBody
    }

    @ViewBuilder
    private var cardBody: some View {
        if let step = currentStep, step.tipID != dismissedTipID {
            HStack(spacing: 12) {
                Image(systemName: step.icon(for: activeSport))
                    .font(.title3)
                    .foregroundStyle(step.color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title(for: activeSport))
                        .font(.headingSmall)

                    Text(step.message(for: activeSport))
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    postSwitchTab(step.tab)
                } label: {
                    Text(step.buttonLabel(for: activeSport))
                        .font(.headingSmall)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(step.color.opacity(0.2))
                        .foregroundStyle(step.color)
                        .clipShape(Capsule())
                }

                Button {
                    withAnimation {
                        OnboardingManager.shared.dismissTip(step.tipID)
                        dismissedTipID = step.tipID
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
                    .fill(step.color.opacity(0.1))
            }
        }
    }
}
