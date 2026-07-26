//
//  RecruitingReadinessSection.swift
//  PlayerPath
//
//  The last checkpoint before a recruiting profile goes public: the handful of
//  fields a college coach filters on before deciding whether to watch any film,
//  and whether this page carries them.
//
//  Publish itself has no minimum bar and shouldn't get one — the house
//  convention is that the action stays live and the copy carries the cost (see
//  RecruitingPublishView's header on why gating recruiting screens goes wrong).
//  So this warns, never blocks.
//

import SwiftUI

/// One line of the pre-publish checklist.
struct RecruitingReadinessItem: Identifiable {
    let id: String
    let label: String
    let isDone: Bool
    /// Shown under an unmet item: what its absence COSTS, not what to type. Nil
    /// for the items that are merely incomplete — spending a sentence on every
    /// row would flatten the two that actually change whether a coach responds.
    let consequence: String?
}

enum RecruitingReadiness {
    /// The checklist for one profile, ordered by what a coach filters on first.
    ///
    /// Deliberately does NOT include highlight clips: `canPublish` already
    /// requires a non-empty selection, so a clips row could never be unticked
    /// here and would read as filler.
    static func items(for info: RecruitingInfo, sport: Sport) -> [RecruitingReadinessItem] {
        var items: [RecruitingReadinessItem] = [
            .init(id: "gradYear",
                  label: "Graduation year",
                  isDone: info.gradYear != nil,
                  consequence: "Recruiting class is the first thing a coach filters on.")
        ]
        // Golf has no positions, so a golf profile drops the row rather than
        // showing a box that can never be ticked — a permanently-unmet item reads
        // as a bug in the app, and it would also make every golf profile look
        // incomplete forever. Same reasoning that hides the baseball measurables
        // card for golfers (P4.10).
        if sport != .golf {
            items.append(.init(id: "position",
                               label: "Position",
                               isDone: info.positionLine != nil,
                               consequence: nil))
        }
        items.append(.init(id: "school",
                           label: "High school",
                           isDone: info.highSchool?.isEmpty == false,
                           consequence: nil))
        items.append(.init(id: "headshot",
                           label: "Headshot",
                           isDone: info.headshotCloudURL != nil,
                           consequence: "Without one, a shared link unfurls in a coach's inbox as a plain row of text."))
        // `hasPublicReplyChannel`, not `visibleContactItems` — the latter counts
        // GPA, and a page showing a GPA and nothing else is not reachable.
        items.append(.init(id: "contact",
                           label: "Email or phone",
                           isDone: info.hasPublicReplyChannel,
                           consequence: "A coach who scans your QR code has no way to reach you."))
        return items
    }
}

/// Pre-publish checklist. Renders only while something is unmet — the app's
/// convention is to surface a problem and stay quiet otherwise (see the
/// stale-highlight nudge and the status-unavailable row), and a permanent
/// all-green section is just furniture on a screen an athlete revisits.
struct RecruitingReadinessSection: View {
    let items: [RecruitingReadinessItem]
    /// True while a publish/unpublish/delete is in flight. Holds the button only,
    /// not the rows: every other action on the publish screen is held the same way,
    /// and leaving mid-publish via an app action that reads "go edit these fields"
    /// drops the athlete somewhere with no sign of whether the publish landed.
    var isBusy: Bool = false
    /// Pops back to the editor — the only screen where these fields are editable,
    /// and one tap away, so the checklist doesn't dead-end the way the page it's
    /// describing would.
    let onFillIn: () -> Void

    @Environment(\.ppAccent) private var ppAccent

    private var doneCount: Int { items.filter(\.isDone).count }

    /// Rolls the row into one announcement, consequence included.
    ///
    /// `.accessibilityElement(children: .combine)` plus a plain label would REPLACE
    /// the combined children, silently dropping the consequence line — so the two
    /// rows that actually explain what an athlete is giving up would be the two
    /// VoiceOver never reads. Same class of miss as P4.6.
    private static func accessibilityLabel(for item: RecruitingReadinessItem) -> String {
        let state = item.isDone ? "added" : "missing"
        guard !item.isDone, let consequence = item.consequence else {
            return "\(item.label), \(state)"
        }
        return "\(item.label), \(state). \(consequence)"
    }

    var body: some View {
        Section {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isDone ? ppAccent : Color.secondary)
                        // The label already says added/missing — a second
                        // announcement for the glyph is noise.
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(.bodyMedium)
                            .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                        if !item.isDone, let consequence = item.consequence {
                            Text(consequence)
                                .font(.bodySmall)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Self.accessibilityLabel(for: item))
            }

            Button(action: onFillIn) {
                Text("Fill These In")
            }
            .disabled(isBusy)
        } header: {
            Text("Profile Readiness — \(doneCount) of \(items.count)")
        } footer: {
            Text("You can publish without these. Coaches use them to decide whether your film is worth opening at all.")
        }
    }
}
