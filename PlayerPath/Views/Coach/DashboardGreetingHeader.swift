//
//  DashboardGreetingHeader.swift
//  PlayerPath
//
//  Time-of-day greeting + most-important pending action for the coach
//  dashboard. Replaces the bare nav title with something actionable.
//

import SwiftUI

struct DashboardGreetingHeader: View {
    @Environment(\.ppAccent) private var ppAccent

    let displayName: String?
    let needsReviewCount: Int
    let draftCount: Int
    let isLiveSession: Bool
    let isReviewingSession: Bool
    let nextScheduledDate: Date?
    /// New coach with no athletes or sessions yet.
    var isEmptyState: Bool = false
    /// Empty-state refinements so the subtitle tracks invite progress.
    var hasSentInvite: Bool = false
    var hasReceivedInvite: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.ppTitle2)
                .foregroundStyle(Theme.textPrimary)

            Text(subtitle)
                .font(.ppSubheadline)
                .foregroundStyle(subtitleColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var firstName: String {
        guard let name = displayName, !name.isEmpty else { return "Coach" }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let tod: String
        switch hour {
        case 5..<12:  tod = "Good morning"
        case 12..<17: tod = "Good afternoon"
        default:      tod = "Good evening"
        }
        return "\(tod), \(firstName)"
    }

    private var subtitle: String {
        if needsReviewCount > 0 {
            return "\(needsReviewCount) clip\(needsReviewCount == 1 ? "" : "s") need your review"
        }
        if isLiveSession {
            return "Session in progress"
        }
        if isReviewingSession {
            return "Review or complete your session"
        }
        if let date = nextScheduledDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Next session \(formatter.localizedString(for: date, relativeTo: Date()))"
        }
        if draftCount > 0 {
            return "\(draftCount) draft\(draftCount == 1 ? "" : "s") to review"
        }
        if isEmptyState {
            if hasReceivedInvite { return "An athlete invited you — accept above" }
            if hasSentInvite { return "Invite sent — waiting for them to accept" }
            return "Invite your first athlete to get started"
        }
        return "Ready when you are"
    }

    private var subtitleColor: Color {
        needsReviewCount > 0 ? ppAccent : Theme.textSecondary
    }
}
