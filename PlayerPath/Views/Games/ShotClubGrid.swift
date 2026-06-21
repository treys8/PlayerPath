//
//  ShotClubGrid.swift
//  PlayerPath
//
//  Full-bag club picker for shot-by-shot entry. Every club is always shown; the
//  ~4 recommended (from ShotClubRecommender) get a ★ + accent ring. One tap
//  selects. Kept separate so ShotEntryView stays focused on flow + state.
//

import SwiftUI

struct ShotClubGrid: View {
    let selected: Club?
    let recommended: Set<Club>
    let onSelect: (Club) -> Void

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 7)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 7) {
            ForEach(Club.allCases, id: \.self) { club in
                ClubChip(
                    club: club,
                    isSelected: selected == club,
                    isRecommended: recommended.contains(club),
                    onTap: { onSelect(club) }
                )
            }
        }
    }
}

private struct ClubChip: View {
    let club: Club
    let isSelected: Bool
    let isRecommended: Bool
    let onTap: () -> Void

    private var fillColor: Color {
        isSelected ? Theme.golfAccent : Color(.secondarySystemBackground)
    }
    private var ringColor: Color {
        (isRecommended && !isSelected) ? Theme.golfAccent.opacity(0.55) : .clear
    }
    private var showsStar: Bool { isRecommended && !isSelected }

    private var label: some View {
        Text(club.shortName)
            .font(.bodyMedium)
            .fontWeight(isSelected ? .bold : .medium)
            .foregroundColor(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: .cornerMedium).fill(fillColor))
            .overlay(RoundedRectangle(cornerRadius: .cornerMedium).stroke(ringColor, lineWidth: 1.5))
            .overlay(alignment: .topTrailing) { star }
    }

    @ViewBuilder private var star: some View {
        if showsStar {
            Text("★")
                .font(.system(size: 9))
                .foregroundColor(Theme.golfAccent)
                .padding(2)
        }
    }

    var body: some View {
        Button {
            Haptics.selection()
            onTap()
        } label: {
            label
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(club.accessibilityLabel + (isRecommended ? ", recommended" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
