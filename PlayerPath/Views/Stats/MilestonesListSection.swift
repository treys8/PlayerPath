//
//  MilestonesListSection.swift
//  PlayerPath
//
//  Visual overhaul — the Stats "Milestones" list.
//  Renders the computed milestones for the selected season/career as a cream
//  card list: an accent star marker (PPMilestoneMarker) + serif title + muted
//  context line. Purely presentational; the engine does all the work. Renders
//  nothing when there are no milestones, so the caller can drop it in
//  unconditionally.
//

import SwiftUI

struct MilestonesListSection: View {
    let milestones: [Milestone]

    var body: some View {
        if !milestones.isEmpty {
            VStack(alignment: .leading, spacing: .spacingMedium) {
                PPSectionHeader("Milestones", overline: "The season so far")

                VStack(spacing: 0) {
                    ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                        if index > 0 {
                            Divider().overlay(Theme.divider)
                        }
                        row(milestone)
                    }
                }
                .padding(.spacingLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ppCard()
            }
        }
    }

    private func row(_ milestone: Milestone) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PPMilestoneMarker(label: milestone.markerLabel)
            Text(milestone.title)
                .font(.ppHeadline)
                .foregroundStyle(Theme.textPrimary)
            if let detail = milestone.detail {
                Text(detail)
                    .font(.ppFootnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, .spacingMedium)
    }
}
