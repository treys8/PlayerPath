//
//  RecruitingShareCard.swift
//  PlayerPath
//
//  Presentation pieces for the Share Profile screen: the live-link card and the
//  view-activity tiles. Split out of RecruitingPublishView, which carries the
//  publish/paywall/consent logic and the comments explaining why it's shaped the
//  way it is — layout doesn't belong in there too.
//
//  These views own no navigation and no error state. They take a URL and hand
//  taps back up, so the screen stays the single place that knows about sheets,
//  tiers and alerts.
//

import SwiftUI
import UIKit

// MARK: - Action tile

/// One secondary action in the share row. The label sits under the icon and the
/// tile takes `maxWidth: .infinity`, so a row of these is evenly divided no
/// matter how long the individual titles are.
///
/// The previous layout let each button size to its own label, which put "Share"
/// next to "Copy" and "QR Code" next to a nearly full-width "Email a Coach" —
/// four controls, no two the same width, reading as an accident rather than a
/// set. Titles here stay short for the same reason.
struct RecruitingActionTile: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.labelMedium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Live link card

/// The "your profile is live" card: status, the link, and the verbs that put it
/// in a coach's hands.
struct RecruitingShareCard: View {
    let url: URL
    /// Named in the status line: on a multi-athlete account "Your profile is live"
    /// doesn't say whose page this link opens, and the link is about to be sent to
    /// college coaches.
    let athleteName: String
    /// Drives both the status line and whether any share verb appears at all.
    /// Not merely cosmetic: serveRecruitingProfile re-reads the owner's tier on
    /// every render, so a lapsed account's page is dark even while
    /// `isPublished` is still true. Handing a college coach a link that shows
    /// "profile unavailable" is worse than not sharing at all — the URL still
    /// shows (it's theirs, and it returns on renewal), just not the buttons.
    let isPro: Bool
    let sport: Sport?
    let onShowQR: () -> Void
    /// Nil when no `mailto:` could be built — the tile is dropped rather than
    /// shown dead, and the row simply divides between the remaining two.
    let onEmail: (() -> Void)?

    @Environment(\.ppAccent) private var ppAccent
    @State private var copied: CopyTarget?

    private enum CopyTarget { case link, bio }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(isPro ? "\(athleteName)'s profile is live" : "\(athleteName)'s profile is offline",
                  systemImage: isPro ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.headingMedium)
                .foregroundStyle(isPro ? ppAccent : Theme.warning)

            // One line: wrapped to two lines of uppercase hex, the share token
            // swamped the card. Displayed scheme-less and cut from the tail so
            // the domain survives — see RecruitingShareTools.displayLink. Copy,
            // right below, is how the link actually travels.
            Text(RecruitingShareTools.displayLink(url))
                .font(.bodySmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)

            if isPro {
                // Each verb carries its own `?s=` marker so the server can bucket
                // views by channel. The URL DISPLAYED above stays untagged.
                ShareLink(item: RecruitingShareTools.taggedURL(url, channel: .share)) {
                    Label("Share Profile Link", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack(spacing: 10) {
                    RecruitingActionTile(
                        title: copied == .link ? "Copied" : "Copy",
                        systemImage: copied == .link ? "checkmark" : "doc.on.doc"
                    ) {
                        copy(RecruitingShareTools.taggedURL(url, channel: .copy).absoluteString, as: .link)
                    }

                    RecruitingActionTile(title: "QR Code", systemImage: "qrcode", action: onShowQR)

                    if let onEmail {
                        RecruitingActionTile(title: "Email", systemImage: "envelope", action: onEmail)
                    }
                }

                Divider()

                // Was a "tap and hold to copy" instruction in the section footer,
                // sitting above the full blurb — which meant the URL appeared on
                // this screen twice and the only way to act on it was a gesture
                // nothing advertised. Same tool, as a control.
                Button {
                    copy(RecruitingShareTools.bioBlurb(sport: sport, url: url), as: .bio)
                } label: {
                    HStack {
                        Label(copied == .bio ? "Bio copied" : "Copy bio for Instagram / X",
                              systemImage: copied == .bio ? "checkmark" : "text.quote")
                            .font(.bodyMedium)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(ppAccent)
            }
        }
        .padding(.vertical, 4)
    }

    private func copy(_ string: String, as target: CopyTarget) {
        UIPasteboard.general.string = string
        Haptics.light()
        withAnimation { copied = target }
        // Confirmation reverts on its own. Guarded on the target so a second
        // copy of the other thing doesn't get its checkmark cleared early by
        // the first one's timer.
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == target {
                withAnimation { copied = nil }
            }
        }
    }
}

// MARK: - Activity tiles

/// Total / this-week views with the last-viewed time beneath. The counts come
/// off the profile doc (written by serveRecruitingProfile, pruned by
/// recruitingViewDigest); link unfurlers and bots are excluded server-side.
///
/// Two tiles rather than three: "2 hours ago" is prose, not a figure, and
/// squeezing it into a numeric tile made all three unreadable.
struct RecruitingActivityTiles: View {
    let totalViews: Int
    let viewsThisWeek: Int
    let lastViewedAt: Date?

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                tile(title: "Total views", value: "\(totalViews)")
                Divider().frame(height: 42)
                tile(title: "This week", value: "\(viewsThisWeek)")
            }

            if let lastViewedAt {
                Text("Last viewed \(lastViewedAt.formatted(.relative(presentation: .named)))")
                    .font(.labelSmall)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func tile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.ppStatMedium)
                .foregroundStyle(ppAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.labelMedium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}
