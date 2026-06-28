//
//  DrillCardTabView.swift
//  PlayerPath
//
//  Drill Card tab inside CoachVideoPlayerView — list of saved drill cards
//  with a "New Drill Card" entry point.
//

import SwiftUI

struct DrillCardTabView: View {
    let drillCards: [DrillCard]
    /// True only for a folder coach with comment permission (not the folder-owner
    /// athlete). Gates the "New Drill Card" button — drill cards are coach
    /// feedback, so the athlete sees them read-only.
    let canManageCards: Bool
    let onAdd: () -> Void
    /// Coach-only per-card edit/delete. Wired only when `canManageCards`; the
    /// athlete (read-only) side leaves these nil so no overflow menu shows.
    var onEdit: ((DrillCard) -> Void)? = nil
    var onDelete: ((DrillCard) -> Void)? = nil
    /// The signed-in user's id. Edit/Delete surface only on cards authored by
    /// this user — firestore.rules permit update/delete only by the creating
    /// coach, so showing them on another coach's card would dead-end in
    /// permission-denied. For an athlete viewer this never matches a card's
    /// coachID, so it stays hidden (and onEdit/onDelete are nil there anyway).
    var currentCoachID: String? = nil
    /// Inline (portrait phone): natural-height empty state, no internal scroll —
    /// the page's outer ScrollView handles it. Sidebar (false): self-scrolls
    /// inside the fixed-height sidebar region.
    var inline: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if canManageCards {
                Button(action: onAdd) {
                    Label("New Drill Card", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandNavy.opacity(0.1))
                        .foregroundColor(.brandNavy)
                }
            }

            Divider()

            if drillCards.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 50))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No drill cards yet")
                        .font(.headline)
                    Text("Create a structured review with ratings for specific skills.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .tabStateFrame(inline: inline)
            } else if inline {
                cardList
            } else {
                ScrollView { cardList }
            }
        }
    }

    private var cardList: some View {
        LazyVStack(spacing: 12) {
            ForEach(drillCards) { card in
                let isAuthor = currentCoachID != nil && card.coachID == currentCoachID
                DrillCardSummaryView(
                    card: card,
                    onEdit: isAuthor ? onEdit.map { edit in { edit(card) } } : nil,
                    onDelete: isAuthor ? onDelete.map { del in { del(card) } } : nil
                )
            }
        }
        .padding()
    }
}
