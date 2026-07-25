//
//  RecruitingShareTools.swift
//  PlayerPath
//
//  The outreach helpers around a published recruiting profile: a pre-written
//  intro email to a college coach, a copy-paste bio blurb for social profiles,
//  and the post-publish success sheet that catches the athlete at the moment
//  they're most motivated to actually send the link somewhere.
//

import SwiftUI

// MARK: - Builders

enum RecruitingShareTools {

    /// `mailto:` with a coach-ready subject and body — the athlete only adds
    /// the recipient. Built from the same RecruitingInfo display helpers the
    /// page uses, so the subject line matches what the coach will open.
    static func coachEmailURL(athleteName: String, info: RecruitingInfo, isGolf: Bool, url: URL) -> URL? {
        var subjectParts = [athleteName]
        if let subline = info.subline(isGolf: isGolf) { subjectParts.append(subline) }
        subjectParts.append("Game Film")
        let subject = subjectParts.joined(separator: " — ")

        var lines = ["Coach,", ""]
        var intro = "I'm \(athleteName)"
        if let schoolLine = info.schoolLine { intro += " (\(schoolLine))" }
        intro += " and I'm interested in your program."
        lines.append(intro)
        lines.append("")
        lines.append("My game film, measurables, and contact info are here:")
        lines.append(url.absoluteString)
        lines.append("")
        lines.append("Thank you for your time.")
        lines.append(athleteName)
        let body = lines.joined(separator: "\n")

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    /// One-liner for a Twitter/Instagram bio — where recruiters actually scout.
    static func bioBlurb(sport: Sport?, url: URL) -> String {
        let emoji: String
        switch sport {
        case .golf: emoji = "⛳️"
        case .softball: emoji = "🥎"
        default: emoji = "⚾️"
        }
        return "\(emoji) Game film & recruiting profile: \(url.absoluteString)"
    }
}

// MARK: - Post-publish success sheet

/// Shown the moment a publish lands. The link is at peak relevance right now —
/// dismissing back to a Form with the verbs buried in a section footer would
/// waste the one moment the athlete is guaranteed to be thinking about sharing.
struct RecruitingPublishSuccessView: View {
    let athlete: Athlete
    let url: URL
    /// Clips the athlete picked that couldn't be published (file missing from
    /// cloud storage). Surfaced here instead of a competing alert.
    let skippedClipCount: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccent) private var ppAccent

    @State private var showingQR = false
    @State private var copied = false
    @State private var emailUnavailable = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 8)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(ppAccent)

                VStack(spacing: 6) {
                    Text("Your profile is live")
                        .font(.headingLarge)
                    Text(url.absoluteString)
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                if skippedClipCount > 0 {
                    Label(
                        "\(skippedClipCount) clip\(skippedClipCount == 1 ? "" : "s") couldn't be included — the video isn't in your cloud storage any more. Everything else is live.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    ShareLink(item: url) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if let emailURL = coachEmailURL {
                        Button {
                            // No mail app configured → open() fails silently;
                            // fall back to copying the link so the tap always
                            // does SOMETHING on the peak-motivation sheet.
                            UIApplication.shared.open(emailURL, options: [:]) { opened in
                                if !opened {
                                    UIPasteboard.general.string = url.absoluteString
                                    emailUnavailable = true
                                }
                            }
                        } label: {
                            Label("Email a College Coach", systemImage: "envelope")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    if emailUnavailable {
                        Text("No mail app is set up on this device — your profile link was copied instead.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        showingQR = true
                    } label: {
                        Label("Show QR Code", systemImage: "qrcode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        UIPasteboard.general.string = url.absoluteString
                        Haptics.light()
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .background(Theme.surface)
            .tint(ppAccent)
            .ppAccent(for: athlete.sport)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingQR) {
                RecruitingQRCodeView(athleteName: athlete.name, url: url)
            }
        }
        .presentationDetents([.large])
    }

    private var coachEmailURL: URL? {
        RecruitingShareTools.coachEmailURL(
            athleteName: athlete.name,
            info: athlete.recruiting,
            isGolf: (athlete.sport ?? .baseball) == .golf,
            url: url
        )
    }
}
