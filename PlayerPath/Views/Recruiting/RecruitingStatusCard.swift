//
//  RecruitingStatusCard.swift
//  PlayerPath
//
//  The top of the recruiting editor: is the page live, how many coaches have
//  looked, and is the page behind what's been typed here. Once a profile is live
//  that is what an athlete comes back for — it used to sit at the bottom of a
//  long form, under every bio field. It's also where the "your profile was
//  viewed" push lands, since that push opens this editor.
//
//  Owns no navigation: every action is handed back up, so the editor stays the
//  one place that persists before pushing Share Profile.
//

import SwiftUI

struct RecruitingStatusCard: View {
    let status: RecruitingPublishStatus?
    let isPro: Bool
    /// Local edits the live page doesn't show yet.
    let hasUnpublishedChanges: Bool
    /// Flagged highlights that aren't on the live page.
    let staleHighlightCount: Int
    /// "Live since Feb 3, 2026 · updated Jul 26, 2026", or nil.
    let liveSinceText: String?
    /// Headshot upload in flight — publishing now would ship without it.
    let isBusy: Bool
    let onOpenShare: () -> Void
    let onRenew: () -> Void

    @Environment(\.ppAccent) private var ppAccent

    private var isPublished: Bool { status?.isPublished == true }

    var body: some View {
        Section {
            if isPublished && isPro {
                liveContent
            } else if isPublished {
                // The CF re-reads the owner's tier per render, so a lapsed page is
                // dark even though isPublished is still true.
                headline("Offline — Pro ended", systemImage: "exclamationmark.triangle.fill",
                         color: Theme.warning,
                         detail: "Coaches who open your link see \"profile unavailable\". Renew to bring it back — the link doesn't change.")
                Button("Renew Pro", action: onRenew)
                shareButton("Share Profile")
            } else if status != nil {
                headline("Unpublished", systemImage: "pause.circle.fill", color: .secondary,
                         detail: "Your link is paused. Publish again from Share Profile — it's the same link.")
                shareButton("Share Profile")
            } else {
                headline("Not published yet", systemImage: "globe", color: .secondary,
                         detail: "Publish to get a link you can send to college coaches.")
                shareButton("Publish Profile")
            }
        }
    }

    // MARK: - States

    @ViewBuilder
    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Live", systemImage: "checkmark.seal.fill")
                .font(.headingMedium)
                .foregroundStyle(ppAccent)
            if let status {
                Text("\(status.viewCount) view\(status.viewCount == 1 ? "" : "s") · \(status.viewsThisWeek) this week")
                    .font(.bodySmall)
            }
            if let liveSinceText {
                Text(liveSinceText)
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)

        if hasUnpublishedChanges {
            nudgeRow(title: "Your changes aren't on your page yet",
                     detail: "Coaches still see the last version you published.")
        }
        if staleHighlightCount > 0 {
            nudgeRow(title: staleHighlightCount == 1
                        ? "1 new highlight isn't on your page yet"
                        : "\(staleHighlightCount) new highlights aren't on your page yet",
                     detail: "Update to put your best film in front of coaches.")
        }
        shareButton("Share Profile")
    }

    // MARK: - Pieces

    private func headline(_ title: String, systemImage: String, color: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.headingMedium)
                .foregroundStyle(color)
            Text(detail)
                .font(.bodySmall)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// "Out of date" row. Lands on Share Profile, where Update lives — publishing
    /// is never one blind tap from here.
    private func nudgeRow(title: String, detail: String) -> some View {
        Button(action: onOpenShare) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.bodySmall)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text("Update")
                    .font(.bodySmall.weight(.semibold))
                    .foregroundStyle(ppAccent)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func shareButton(_ title: String) -> some View {
        Button(action: onOpenShare) {
            Label(title, systemImage: title == "Publish Profile" ? "paperplane" : "square.and.arrow.up")
        }
        .disabled(isBusy)
    }
}
