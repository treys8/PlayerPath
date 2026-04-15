//
//  DashboardGreetingHeader.swift
//  PlayerPath
//
//  Time-of-day greeting + most-important pending action for the coach
//  dashboard. Replaces the bare nav title with something actionable.
//

import SwiftUI

struct DashboardGreetingHeader: View {
    let displayName: String?
    let needsReviewCount: Int
    let draftCount: Int
    let hasActiveSession: Bool
    let nextScheduledDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(subtitleColor)
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
        if hasActiveSession {
            return "Session in progress"
        }
        if let date = nextScheduledDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Next session \(formatter.localizedString(for: date, relativeTo: Date()))"
        }
        if draftCount > 0 {
            return "\(draftCount) draft\(draftCount == 1 ? "" : "s") to review"
        }
        return "Ready when you are"
    }

    private var subtitleColor: Color {
        needsReviewCount > 0 ? .orange : .secondary
    }
}
