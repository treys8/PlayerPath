//
//  ClipReviewDrillSection.swift
//  PlayerPath
//
//  Collapsible drill-card section for ClipReviewSheet. Lets the coach
//  attach drill cards while the clip is still private; writes go straight
//  to the videos/{id}/drillCards subcollection (athlete can't see them
//  until the clip is published, and the CF suppresses notifications for
//  private clips).
//

import SwiftUI

struct ClipReviewDrillSection: View {
    let drillCards: [DrillCard]
    let isLoading: Bool
    @Binding var isExpanded: Bool
    let onAdd: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading drill cards…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 6)
                } else if drillCards.isEmpty {
                    Text("Add a structured review with skill ratings.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 6)
                } else {
                    ForEach(drillCards) { card in
                        DrillCardSummaryView(card: card)
                    }
                }

                Button(action: onAdd) {
                    Label(drillCards.isEmpty ? "New Drill Card" : "Add Another Drill Card",
                          systemImage: "plus.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.brandNavy.opacity(0.1))
                        .foregroundColor(.brandNavy)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 4)
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Label(headerTitle, systemImage: "clipboard")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    private var headerTitle: String {
        drillCards.isEmpty ? "Drill Card" : "Drill Card • \(drillCards.count)"
    }
}
