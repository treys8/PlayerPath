//
//  GettingStartedView.swift
//  PlayerPath
//
//  Getting started guide for new users
//

import SwiftUI

struct GettingStartedView: View {
    @Environment(\.ppAccent) private var ppAccent
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    private var isCoach: Bool { authManager.userRole == .coach }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    Text(isCoach ? "Getting Started as a Coach" : "Getting Started with PlayerPath")
                        .font(.displayLarge)

                    Text(isCoach
                         ? "Welcome! Let's get you set up to connect with athletes and start giving feedback."
                         : "Welcome! Let's get you set up to start tracking your baseball or softball performance.")
                        .font(.bodyLarge)
                        .foregroundColor(.secondary)
                }

                if isCoach {
                    coachSteps
                    coachNextSteps
                } else {
                    athleteSteps
                    athleteNextSteps
                }

                // Help Resources
                VStack(alignment: .leading, spacing: 16) {
                    Text("Need More Help?")
                        .font(.displayMedium)

                    VStack(spacing: 8) {
                        NavigationLink {
                            FAQView()
                        } label: {
                            HelpResourceRow(
                                icon: "questionmark.circle.fill",
                                title: "Frequently Asked Questions",
                                color: .brandNavy
                            )
                        }

                        NavigationLink {
                            HelpView()
                        } label: {
                            HelpResourceRow(
                                icon: "book.fill",
                                title: "Full Help Documentation",
                                color: .green
                            )
                        }

                        NavigationLink {
                            ContactSupportView()
                        } label: {
                            HelpResourceRow(
                                icon: "envelope.fill",
                                title: "Contact Support",
                                color: ppAccent
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Getting Started")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Athlete steps

    @ViewBuilder private var athleteSteps: some View {
        GettingStartedStep(
            number: 1,
            title: "Create Your Athlete Profile",
            icon: "person.fill",
            iconColor: .brandNavy,
            description: "If you haven't already, create your first athlete profile. This represents you or a player you're tracking.",
            steps: [
                "Tap your name at the top of the Dashboard",
                "Select 'Manage Athletes'",
                "Tap '+' to add a new athlete",
                "Enter the athlete's name",
                "Tap 'Create'"
            ]
        )

        GettingStartedStep(
            number: 2,
            title: "Create Your First Season",
            icon: "calendar",
            iconColor: .green,
            description: "Organize your games and videos by season (e.g., 'Spring 2026')",
            steps: [
                "Go to More tab → Seasons",
                "Tap '+' to create a season",
                "Enter season name",
                "Set start date",
                "Choose Baseball or Softball",
                "Toggle 'Make Active' to use this season",
                "Tap 'Create'"
            ],
            tip: "Only one season can be active at a time. New games automatically link to your active season."
        )

        GettingStartedStep(
            number: 3,
            title: "Record Your First Video",
            icon: "video",
            iconColor: .red,
            description: "Capture an at-bat or practice swing",
            steps: [
                "Tap 'Quick Record' on the Dashboard",
                "Camera opens instantly",
                "Record your at-bat or swing",
                "Tap stop when done",
                "Optionally trim the video",
                "Tag the play result (1B, 2B, K, etc.)",
                "Done! Your video is saved"
            ],
            tip: "Hold your device steady or use a tripod for best results. Record in landscape orientation when possible."
        )

        GettingStartedStep(
            number: 4,
            title: "Track a Live Game",
            icon: "baseball.diamond.bases",
            iconColor: ppAccent,
            description: "Create a game and mark it as Live to automatically link all videos",
            steps: [
                "Go to Games tab",
                "Tap '+'",
                "Enter opponent name (e.g., 'Yankees')",
                "Set game date",
                "Toggle 'Start Live' ON",
                "Tap 'Save'",
                "Record videos during the game—they auto-link!",
                "When game is over, tap 'End Game'"
            ],
            tip: "Only one game can be live at a time. Quick Record automatically tags videos to the live game."
        )

        GettingStartedStep(
            number: 5,
            title: "View Your Statistics",
            icon: "chart.bar.fill",
            iconColor: .purple,
            description: "Check your performance metrics",
            steps: [
                "Go to Stats tab",
                "See batting average, slugging, OPS",
                "View season-specific stats",
                "Check per-game performance",
                "Track progress over time"
            ],
            tip: "Stats are calculated automatically from your tagged videos. The more you tag, the more accurate your stats!"
        )
    }

    @ViewBuilder private var athleteNextSteps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Next Steps")
                .font(.displayMedium)

            VStack(alignment: .leading, spacing: 12) {
                NextStepRow(
                    icon: "star.fill",
                    color: .yellow,
                    title: "View Highlights",
                    description: "All hits (1B, 2B, 3B, HR) are automatically saved as highlights"
                )

                NextStepRow(
                    icon: "figure.run",
                    color: .green,
                    title: "Track Practice",
                    description: "Use the Practice tab to log practice sessions"
                )

                NextStepRow(
                    icon: "arrow.triangle.2.circlepath",
                    color: .brandNavy,
                    title: "Sync Across Devices",
                    description: "Sign in on other devices to access your data anywhere"
                )
            }
        }
    }

    // MARK: - Coach steps

    @ViewBuilder private var coachSteps: some View {
        GettingStartedStep(
            number: 1,
            title: "Connect with Your Athletes",
            icon: "person.crop.circle.badge.plus",
            iconColor: .brandNavy,
            description: "Athletes can invite you, or you can invite them.",
            steps: [
                "Open Invitations → 'Received' to accept athletes who invited you",
                "Tap 'Accept' on a pending invitation",
                "Or tap 'Invite Athlete' on your Dashboard",
                "Enter the athlete's name and Parent/Guardian Email",
                "Track invites you've sent in the 'Sent' tab"
            ],
            tip: "Invitations expire after 30 days if they aren't accepted."
        )

        GettingStartedStep(
            number: 2,
            title: "Find Clips to Review",
            icon: "rectangle.stack.badge.play",
            iconColor: .green,
            description: "See the clips your athletes share with you.",
            steps: [
                "Open the 'Needs Your Review' queue on your Dashboard",
                "Open a connected athlete's folder",
                "Games folders show a simple list of shared clips",
                "Lessons folders have 'My Drafts' and 'Shared' tabs",
                "Tap a clip to open it"
            ],
            tip: "You only see clips an athlete shares with you — never their full library or account."
        )

        GettingStartedStep(
            number: 3,
            title: "Leave Feedback",
            icon: "pencil.and.outline",
            iconColor: .red,
            description: "Give feedback your athlete can act on.",
            steps: [
                "Write a note on the clip",
                "Tap the pencil to draw on a frame (telestration)",
                "Build a drill card with 1–5 ratings",
                "Apply a quick cue like 'Stay back'"
            ],
            tip: "Feedback reaches your athlete in real time. In this version, feedback is one-way (coach to athlete)."
        )

        GettingStartedStep(
            number: 4,
            title: "Run a Live Session",
            icon: "dot.radiowaves.left.and.right",
            iconColor: ppAccent,
            description: "Capture clips during an in-person lesson.",
            steps: [
                "Tap 'New Session' on your Dashboard",
                "Pick one or more athletes",
                "Optionally set a date and add session notes",
                "Start the session to go live",
                "Tap 'Record' to capture clips"
            ],
            tip: "Clips you record start as drafts — Publish them to share with the athlete."
        )

        GettingStartedStep(
            number: 5,
            title: "Manage Your Plan",
            icon: "person.3.fill",
            iconColor: .purple,
            description: "See your tier and how many athletes you can coach.",
            steps: [
                "Open Profile → Subscription",
                "See your plan and athlete count",
                "Tap 'Upgrade Plan' or 'Manage Plan' to change",
                "Free 2 · Instructor 10 · Pro Instructor 30 · Academy unlimited"
            ],
            tip: "If you downgrade over your limit, you get a 7-day grace period to choose which athletes to keep."
        )
    }

    @ViewBuilder private var coachNextSteps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Next Steps")
                .font(.displayMedium)

            VStack(alignment: .leading, spacing: 12) {
                NextStepRow(
                    icon: "text.bubble.fill",
                    color: .yellow,
                    title: "Quick Cues",
                    description: "Save short reusable coaching phrases you can tap onto any clip"
                )

                NextStepRow(
                    icon: "checklist",
                    color: .green,
                    title: "Drill Cards",
                    description: "Build structured, repeatable feedback with ratings and notes"
                )

                NextStepRow(
                    icon: "arrow.triangle.2.circlepath",
                    color: .brandNavy,
                    title: "Sync Across Devices",
                    description: "Sign in on other devices to access your athletes anywhere"
                )
            }
        }
    }
}

struct GettingStartedStep: View {
    let number: Int
    let title: String
    let icon: String
    let iconColor: Color
    let description: String
    let steps: [String]
    var tip: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconColor)
                        .frame(width: 50, height: 50)

                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Step \(number)")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)

                    Text(title)
                        .font(.headingLarge)
                }
            }

            Text(description)
                .font(.bodyLarge)
                .foregroundColor(.secondary)

            // Steps
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.bodyLarge)
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .leading)

                        Text(step)
                            .font(.bodyLarge)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 8)

            // Tip
            if let tip = tip {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)

                    Text(tip)
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct NextStepRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.labelLarge)

                Text(description)
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct HelpResourceRow: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)

            Text(title)
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    NavigationStack {
        GettingStartedView()
            .environmentObject(ComprehensiveAuthManager())
    }
}
