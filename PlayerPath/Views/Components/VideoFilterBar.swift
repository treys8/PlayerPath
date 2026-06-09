//
//  VideoFilterBar.swift
//  PlayerPath
//
//  Combinable quick-filter chip bar for the Videos tab. Replaces the old
//  single-select VideoLibraryFilter pill row. Toggle chips (Highlights / Coach /
//  Untagged) plus a sport-aware menu chip (Result for baseball/softball, Club for
//  golf) and an Opponent menu chip. All dimensions AND together — see
//  `VideoClipFilter`.
//

import SwiftUI

struct VideoFilterBar: View {
    @Binding var filter: VideoClipFilter
    let sport: Season.SportType
    let opponents: [String]

    private var isGolf: Bool { sport == .golf }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacingSmall) {
                VideoFilterChip(icon: "square.grid.2x2", title: "All", isSelected: !filter.isActive) {
                    withAnimation { filter = VideoClipFilter() }
                    Haptics.light()
                }

                VideoFilterChip(icon: "star.fill", title: "Highlights", isSelected: filter.highlightsOnly) {
                    withAnimation { filter.highlightsOnly.toggle() }
                    Haptics.light()
                }

                VideoFilterChip(icon: "text.bubble.fill", title: "Coach", isSelected: filter.coachFeedbackOnly) {
                    withAnimation { filter.coachFeedbackOnly.toggle() }
                    Haptics.light()
                }

                VideoFilterChip(icon: "tag.slash", title: "Untagged", isSelected: filter.untaggedOnly) {
                    withAnimation { filter.untaggedOnly.toggle() }
                    Haptics.light()
                }

                if isGolf {
                    clubMenu
                } else {
                    resultMenu
                }

                if !opponents.isEmpty {
                    opponentMenu
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Theme.surface)
    }

    // MARK: - Result menu (baseball/softball)

    private var resultMenu: some View {
        Menu {
            menuRow("Any Result", active: filter.result == .any) { setResult(.any) }
            Section {
                menuRow("Hits", active: filter.result == .hits) { setResult(.hits) }
                menuRow("On Base", active: filter.result == .onBase) { setResult(.onBase) }
                menuRow("Outs", active: filter.result == .outs) { setResult(.outs) }
            }
            Section("Batting") {
                menuRow("All Batting", active: filter.result == .batting) { setResult(.batting) }
                ForEach(PlayResultType.battingCases, id: \.self) { t in
                    menuRow(t.displayName, active: filter.result == .specific(t)) { setResult(.specific(t)) }
                }
            }
            Section("Pitching") {
                menuRow("All Pitching", active: filter.result == .pitching) { setResult(.pitching) }
                ForEach(PlayResultType.pitchingCases, id: \.self) { t in
                    menuRow(t.displayName, active: filter.result == .specific(t)) { setResult(.specific(t)) }
                }
            }
        } label: {
            VideoFilterChipLabel(icon: "baseball", title: filter.result.label ?? "Result",
                            isSelected: filter.result != .any, showsChevron: true)
        }
    }

    private func setResult(_ value: VideoClipFilter.ResultFilter) {
        withAnimation { filter.result = value }
        Haptics.light()
    }

    // MARK: - Club menu (golf)

    private var clubMenu: some View {
        Menu {
            menuRow("Any Club", active: filter.club == .any) { setClub(.any) }
            ForEach(Club.Category.allCases, id: \.self) { cat in
                Section(cat.displayName) {
                    menuRow("All \(cat.displayName.capitalized)", active: filter.club == .category(cat)) {
                        setClub(.category(cat))
                    }
                    ForEach(Club.cases(in: cat), id: \.self) { club in
                        menuRow(club.displayName, active: filter.club == .specific(club)) {
                            setClub(.specific(club))
                        }
                    }
                }
            }
        } label: {
            VideoFilterChipLabel(icon: "figure.golf", title: filter.club.label ?? "Club",
                            isSelected: filter.club != .any, showsChevron: true)
        }
    }

    private func setClub(_ value: VideoClipFilter.ClubFilter) {
        withAnimation { filter.club = value }
        Haptics.light()
    }

    // MARK: - Opponent menu

    private var opponentMenu: some View {
        Menu {
            menuRow("Any Opponent", active: filter.opponent == nil) { setOpponent(nil) }
            ForEach(opponents, id: \.self) { opponent in
                menuRow(opponent, active: filter.opponent == opponent) { setOpponent(opponent) }
            }
        } label: {
            VideoFilterChipLabel(icon: "person.2.fill",
                            title: filter.opponent.map { "vs \($0)" } ?? "Opponent",
                            isSelected: filter.opponent != nil, showsChevron: true)
        }
    }

    private func setOpponent(_ value: String?) {
        withAnimation { filter.opponent = value }
        Haptics.light()
    }

    // MARK: - Menu row helper (checkmark on the active selection)

    @ViewBuilder
    private func menuRow(_ title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if active {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

// MARK: - Chip primitives

/// Visual capsule used by both toggle chips and menu-label chips. Mirrors the
/// retired `uploadStatusFilterPicker` styling so the bar looks unchanged.
private struct VideoFilterChipLabel: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(title)
                .font(.ppCallout)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
        .foregroundStyle(isSelected ? Theme.surface : Theme.textSecondary)
        .padding(.horizontal, .spacingLarge)
        .padding(.vertical, .spacingSmall)
        .background(Capsule().fill(isSelected ? Theme.textPrimary : Color.clear))
        .overlay(
            Capsule().strokeBorder(isSelected ? Color.clear : Theme.pillBorder, lineWidth: 1)
        )
    }
}

private struct VideoFilterChip: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VideoFilterChipLabel(icon: icon, title: title, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}
