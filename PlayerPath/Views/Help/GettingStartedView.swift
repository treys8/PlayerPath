//
//  GettingStartedView.swift
//  PlayerPath
//
//  Getting started guide for new users
//

import SwiftUI

struct GettingStartedView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    Text("Getting Started with PlayerPath")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Welcome! Let's get you set up to start tracking your baseball or softball performance.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // Step 1
                GettingStartedStep(
                    number: 1,
                    title: "Create Your Athlete Profile",
                    icon: "person.fill",
                    iconColor: .blue,
                    description: "If you haven't already, create your first athlete profile. This represents you or a player you're tracking.",
                    steps: [
                        "Tap your name at the top of the Dashboard",
                        "Select 'Manage Athletes'",
                        "Tap '+' to add a new athlete",
                        "Enter the athlete's name",
                        "Tap 'Create'"
                    ]
                )

                // Step 2
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

                // Step 3
                GettingStartedStep(
                    number: 3,
                    title: "Record Your First Video",
                    icon: "video.fill",
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

                // Step 4
                GettingStartedStep(
                    number: 4,
                    title: "Track a Live Game",
                    icon: "sportscourt.fill",
                    iconColor: .orange,
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

                // Step 5
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

                // Next Steps
                VStack(alignment: .leading, spacing: 16) {
                    Text("Next Steps")
                        .font(.title2)
                        .fontWeight(.bold)

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
                            color: .blue,
                            title: "Sync Across Devices",
                            description: "Sign in on other devices to access your data anywhere"
                        )
                    }
                }

                // Help Resources
                VStack(alignment: .leading, spacing: 16) {
                    Text("Need More Help?")
                        .font(.title2)
                        .fontWeight(.bold)

                    VStack(spacing: 8) {
                        NavigationLink {
                            FAQView()
                        } label: {
                            HelpResourceRow(
                                icon: "questionmark.circle.fill",
                                title: "Frequently Asked Questions",
                                color: .blue
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
                                color: .orange
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
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(title)
                        .font(.headline)
                }
            }

            Text(description)
                .font(.body)
                .foregroundColor(.secondary)

            // Steps
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .leading)

                        Text(step)
                            .font(.body)
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
                        .font(.caption)
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
                    .font(.body)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
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
    }
}
