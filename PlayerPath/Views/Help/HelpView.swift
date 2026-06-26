//
//  HelpView.swift
//  PlayerPath
//
//  Comprehensive help and support system
//

import SwiftUI
import MessageUI

struct HelpView: View {
    @Environment(\.ppAccent) private var ppAccent
    @Environment(\.ppIsGolf) private var isGolf
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    private var isCoach: Bool { authManager.userRole == .coach }

    var body: some View {
        List {
            if isCoach {
                coachSections
            } else {
                athleteSections
            }

            // Shared across roles
            Section("Support") {
                NavigationLink {
                    FAQView()
                } label: {
                    HelpRowLabel(
                        icon: "questionmark.circle.fill",
                        title: "Frequently Asked Questions",
                        subtitle: "Common questions answered"
                    )
                }

                NavigationLink {
                    ContactSupportView()
                } label: {
                    HelpRowLabel(
                        icon: "envelope.fill",
                        title: "Contact Support",
                        subtitle: "Get help from our team"
                    )
                }
            }

            Section {
                VStack(alignment: .center, spacing: 8) {
                    Text("PlayerPath")
                        .font(.headingMedium)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle("Help & Support")
    }

    // MARK: - Athlete content

    @ViewBuilder private var athleteSections: some View {
        Section {
            HelpCard(
                icon: "graduationcap.fill",
                iconColor: ppAccent,
                title: "Getting Started Guide",
                description: "New to PlayerPath? Start here!"
            ) {
                NavigationLink("View Guide") {
                    GettingStartedView()
                }
            }
        }

        Section("Quick Help") {
            NavigationLink {
                HelpArticleDetailView(article: isGolf ? HelpArticle.recordingVideosGolf : .recordingVideos)
            } label: {
                HelpRowLabel(
                    icon: "video",
                    title: "Recording Videos",
                    subtitle: isGolf ? "Capture swings & range sessions" : "Learn how to capture at-bats"
                )
            }

            NavigationLink {
                HelpArticleDetailView(article: isGolf ? HelpArticle.scoringGolf : .taggingPlays)
            } label: {
                HelpRowLabel(
                    icon: isGolf ? "list.bullet.clipboard.fill" : "tag.fill",
                    title: isGolf ? "Scoring Your Round" : "Tagging Play Results",
                    subtitle: isGolf ? "Pars, FIR/GIR & shot tracking" : "Mark hits, outs, and more"
                )
            }

            NavigationLink {
                HelpArticleDetailView(article: isGolf ? HelpArticle.golfStats : .understandingStats)
            } label: {
                HelpRowLabel(
                    icon: "chart.bar.fill",
                    title: isGolf ? "Golf Stats" : "Understanding Statistics",
                    subtitle: isGolf ? "Scoring avg, FIR, GIR, handicap" : "AVG, SLG, OPS explained"
                )
            }
        }

        Section("Managing Data") {
            NavigationLink {
                HelpArticleDetailView(article: HelpArticle.managingAthletes)
            } label: {
                HelpRowLabel(
                    icon: "person.fill",
                    title: "Managing Athletes",
                    subtitle: "Create and switch profiles"
                )
            }

            NavigationLink {
                HelpArticleDetailView(article: isGolf ? HelpArticle.seasonTrackingGolf : .seasonTracking)
            } label: {
                HelpRowLabel(
                    icon: "calendar",
                    title: "Season Tracking",
                    subtitle: isGolf ? "Organize by golf season" : "Organize by season"
                )
            }

            NavigationLink {
                HelpArticleDetailView(article: isGolf ? HelpArticle.roundManagementGolf : .gameManagement)
            } label: {
                HelpRowLabel(
                    icon: isGolf ? "figure.golf" : "baseball.diamond.bases",
                    title: isGolf ? "Rounds & Tournaments" : "Game Management",
                    subtitle: isGolf ? "Rounds, tournaments & practice" : "Track live games"
                )
            }

            NavigationLink {
                HelpArticleDetailView(article: HelpArticle.managingPhotos)
            } label: {
                HelpRowLabel(
                    icon: "photo.fill",
                    title: "Managing Photos",
                    subtitle: "Capture and organize photos"
                )
            }

            NavigationLink {
                HelpArticleDetailView(article: HelpArticle.coachSharing)
            } label: {
                HelpRowLabel(
                    icon: "person.2.fill",
                    title: "Sharing with Coaches",
                    subtitle: "Share clips via shared folders"
                )
            }
        }

        Section("Sync & Storage") {
            syncAndStorageRows
        }

        Section("Account & Privacy") {
            accountAndPrivacyRows
        }
    }

    // MARK: - Coach content

    @ViewBuilder private var coachSections: some View {
        Section {
            HelpCard(
                icon: "graduationcap.fill",
                iconColor: ppAccent,
                title: "Coaching Guide",
                description: "New to coaching on PlayerPath? Start here!"
            ) {
                NavigationLink("View Guide") {
                    GettingStartedView()
                }
            }
        }

        Section("Getting Started") {
            NavigationLink {
                HelpArticleDetailView(article: CoachHelpArticle.coachGettingStarted)
            } label: {
                HelpRowLabel(
                    icon: "graduationcap.fill",
                    title: "Coaching on PlayerPath",
                    subtitle: "How your coach account works"
                )
            }

            NavigationLink {
                HelpArticleDetailView(article: CoachHelpArticle.managingInvitations)
            } label: {
                HelpRowLabel(
                    icon: "person.crop.circle.badge.plus",
                    title: "Connecting with Athletes",
                    subtitle: "Send and accept invitations"
                )
            }
        }

        Section("Reviewing & Feedback") {
            NavigationLink {
                HelpArticleDetailView(article: CoachHelpArticle.reviewingClips)
            } label: {
                HelpRowLabel(
                    icon: "rectangle.stack.badge.play",
                    title: "Reviewing Shared Clips",
                    subtitle: "Find clips athletes share"
                )
            }

            NavigationLink {
                HelpArticleDetailView(article: CoachHelpArticle.leavingFeedback)
            } label: {
                HelpRowLabel(
                    icon: "pencil.and.outline",
                    title: "Leaving Feedback",
                    subtitle: "Notes, drawings, drill cards, cues"
                )
            }

            NavigationLink {
                HelpArticleDetailView(article: CoachHelpArticle.liveSessions)
            } label: {
                HelpRowLabel(
                    icon: "dot.radiowaves.left.and.right",
                    title: "Live Sessions",
                    subtitle: "Capture clips during a lesson"
                )
            }
        }

        Section("Your Plan") {
            NavigationLink {
                HelpArticleDetailView(article: CoachHelpArticle.coachTiersLimits)
            } label: {
                HelpRowLabel(
                    icon: "person.3.fill",
                    title: "Plans & Athlete Limits",
                    subtitle: "Tiers and over-limit behavior"
                )
            }
        }

        Section("Sync & Storage") {
            syncAndStorageRows
        }

        Section("Account & Privacy") {
            accountAndPrivacyRows
        }
    }

    // MARK: - Shared article rows (apply to both roles)

    @ViewBuilder private var syncAndStorageRows: some View {
        NavigationLink {
            HelpArticleDetailView(article: HelpArticle.crossDeviceSync)
        } label: {
            HelpRowLabel(
                icon: "arrow.triangle.2.circlepath",
                title: "Cross-Device Sync",
                subtitle: "Access data anywhere"
            )
        }

        NavigationLink {
            HelpArticleDetailView(article: HelpArticle.videoStorage)
        } label: {
            HelpRowLabel(
                icon: "externaldrive.fill",
                title: "Video Storage",
                subtitle: "Where videos are saved"
            )
        }
    }

    @ViewBuilder private var accountAndPrivacyRows: some View {
        NavigationLink {
            HelpArticleDetailView(article: HelpArticle.exportingData)
        } label: {
            HelpRowLabel(
                icon: "arrow.down.doc",
                title: "Exporting Your Data",
                subtitle: "Download your information"
            )
        }

        NavigationLink {
            HelpArticleDetailView(article: HelpArticle.deletingAccount)
        } label: {
            HelpRowLabel(
                icon: "trash",
                title: "Deleting Your Account",
                subtitle: "Permanent data removal"
            )
        }

        NavigationLink {
            PrivacyPolicyView()
        } label: {
            HelpRowLabel(
                icon: "hand.raised.fill",
                title: "Privacy Policy",
                subtitle: "How we protect your data"
            )
        }

        NavigationLink {
            TermsOfServiceView()
        } label: {
            HelpRowLabel(
                icon: "doc.text.fill",
                title: "Terms of Use (EULA)",
                subtitle: "User agreement"
            )
        }
    }
}

struct HelpCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let content: Content

    init(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(iconColor)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headingLarge)
                    Text(description)
                        .font(.bodyMedium)
                        .foregroundColor(.secondary)
                }
            }

            content
        }
        .padding(.vertical, 4)
    }
}

struct HelpRowLabel: View {
    @Environment(\.ppAccent) private var ppAccent
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(ppAccent)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.bodyLarge)
                Text(subtitle)
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        HelpView()
            .environmentObject(ComprehensiveAuthManager())
    }
}
