import SwiftUI

struct DashboardNextStepCard: View {
    let athlete: Athlete
    @State private var dismissedTipID: String?

    private enum Step {
        case createGame
        case recordVideo

        var tipID: String {
            switch self {
            case .createGame: return "next_step_create_game"
            case .recordVideo: return "next_step_record_video"
            }
        }

        var icon: String {
            switch self {
            case .createGame: return "baseball.diamond.bases"
            case .recordVideo: return "video.badge.plus"
            }
        }

        var color: Color {
            switch self {
            case .createGame: return .green
            case .recordVideo: return .purple
            }
        }

        var title: String {
            switch self {
            case .createGame: return "Log Your First Game"
            case .recordVideo: return "Record Your First Video"
            }
        }

        var message: String {
            switch self {
            case .createGame: return "Start tracking your at-bats and stats by creating a game"
            case .recordVideo: return "Record your swing to review your mechanics"
            }
        }

        var buttonLabel: String {
            switch self {
            case .createGame: return "Games"
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
        if (athlete.games ?? []).isEmpty,
           OnboardingManager.shared.shouldShowTip(Step.createGame.tipID) {
            return .createGame
        }
        if (athlete.videoClips ?? []).isEmpty,
           OnboardingManager.shared.shouldShowTip(Step.recordVideo.tipID) {
            return .recordVideo
        }
        return nil
    }

    var body: some View {
        if let step = currentStep, step.tipID != dismissedTipID {
            HStack(spacing: 12) {
                Image(systemName: step.icon)
                    .font(.title3)
                    .foregroundStyle(step.color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(step.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    postSwitchTab(step.tab)
                } label: {
                    Text(step.buttonLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
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
