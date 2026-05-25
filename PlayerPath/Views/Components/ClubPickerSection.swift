//
//  ClubPickerSection.swift
//  PlayerPath
//
//  Reusable golf club picker section + button. Used by the recording overlay
//  (PlayResultOverlayView when sport == .golf) and by the retro-tag editor
//  (ClubPickerEditorView). Mirrors PlayResultButton's glass-style design but
//  pulls colors from Club.Category.color so the four categories read distinctly.
//

import SwiftUI

struct ClubButton: View {
    let club: Club
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(club.displayName)
                    .font(.headingMedium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.5), radius: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    club.category.color,
                                    club.category.color.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isSelected ? 0.25 : 0.15),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isSelected ? 0.6 : 0.3),
                                Color.white.opacity(isSelected ? 0.3 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: club.category.color.opacity(isSelected ? 0.6 : 0.3),
                    radius: isSelected ? 10 : 5, x: 0, y: isSelected ? 5 : 2)
            .scaleEffect(isPressed ? 0.95 : (isSelected ? 1.02 : 1.0))
        }
        .buttonStyle(ClubButtonStyle(isPressed: $isPressed))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(club.accessibilityLabel))
        .accessibilityHint(Text("Selects this club and asks for confirmation"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ClubButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

/// Category section: header + grid of `ClubButton`s for that category.
/// Three-column grid keeps even the busiest section (Irons, 7 clubs) compact.
struct ClubPickerSection: View {
    let category: Club.Category
    let selected: Club?
    let onSelect: (Club) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlayResultSectionHeader(icon: category.iconName,
                                    title: category.displayName,
                                    color: category.color)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Club.cases(in: category), id: \.self) { club in
                    ClubButton(club: club, isSelected: selected == club) {
                        onSelect(club)
                    }
                }
            }
        }
    }
}
