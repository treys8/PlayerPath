//
//  HelpView.swift
//  PlayerPath
//
//  Comprehensive help and support system
//

import SwiftUI
import MessageUI

struct HelpView: View {
    var body: some View {
        List {
            Section {
                HelpCard(
                    icon: "graduationcap.fill",
                    iconColor: .blue,
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
                    HelpArticleDetailView(article: .recordingVideos)
                } label: {
                    HelpRowLabel(
                        icon: "video",
                        title: "Recording Videos",
                        subtitle: "Learn how to capture at-bats"
                    )
                }

                NavigationLink {
                    HelpArticleDetailView(article: .taggingPlays)
                } label: {
                    HelpRowLabel(
                        icon: "tag.fill",
                        title: "Tagging Play Results",
                        subtitle: "Mark hits, outs, and more"
                    )
                }

                NavigationLink {
                    HelpArticleDetailView(article: .understandingStats)
                } label: {
                    HelpRowLabel(
                        icon: "chart.bar.fill",
                        title: "Understanding Statistics",
                        subtitle: "AVG, SLG, OPS explained"
                    )
                }
            }

            Section("Managing Data") {
                NavigationLink {
                    HelpArticleDetailView(article: .managingAthletes)
                } label: {
                    HelpRowLabel(
                        icon: "person.fill",
                        title: "Managing Athletes",
                        subtitle: "Create and switch profiles"
                    )
                }

                NavigationLink {
                    HelpArticleDetailView(article: .seasonTracking)
                } label: {
                    HelpRowLabel(
                        icon: "calendar",
                        title: "Season Tracking",
                        subtitle: "Organize by season"
                    )
                }

                NavigationLink {
                    HelpArticleDetailView(article: .gameManagement)
                } label: {
                    HelpRowLabel(
                        icon: "sportscourt.fill",
                        title: "Game Management",
                        subtitle: "Track live games"
                    )
                }
            }

            Section("Sync & Storage") {
                NavigationLink {
                    HelpArticleDetailView(article: .crossDeviceSync)
                } label: {
                    HelpRowLabel(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Cross-Device Sync",
                        subtitle: "Access data anywhere"
                    )
                }

                NavigationLink {
                    HelpArticleDetailView(article: .videoStorage)
                } label: {
                    HelpRowLabel(
                        icon: "externaldrive.fill",
                        title: "Video Storage",
                        subtitle: "Where videos are saved"
                    )
                }
            }

            Section("Account & Privacy") {
                NavigationLink {
                    HelpArticleDetailView(article: .exportingData)
                } label: {
                    HelpRowLabel(
                        icon: "arrow.down.doc",
                        title: "Exporting Your Data",
                        subtitle: "Download your information"
                    )
                }

                NavigationLink {
                    HelpArticleDetailView(article: .deletingAccount)
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
                        title: "Terms of Service",
                        subtitle: "User agreement"
                    )
                }
            }

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
                        .font(.headline)
                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Help & Support")
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
                        .font(.headline)
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            content
        }
        .padding(.vertical, 4)
    }
}

struct HelpRowLabel: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        HelpView()
    }
}
