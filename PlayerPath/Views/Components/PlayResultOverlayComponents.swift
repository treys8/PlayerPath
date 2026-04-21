//
//  PlayResultOverlayComponents.swift
//  PlayerPath
//

import SwiftUI

struct PlayResultButton: View {
    let result: PlayResultType
    let isSelected: Bool
    var fullWidth: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    // Glow behind icon when selected
                    if isSelected {
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .blur(radius: 8)
                    }

                    Image(systemName: result.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                }

                // Label
                Text(result.displayName)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.5), radius: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                ZStack {
                    // Base gradient
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    result.color,
                                    result.color.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Shine overlay
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
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

                    // Selection glow
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            .shadow(color: result.color.opacity(isSelected ? 0.6 : 0.3), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            .scaleEffect(isPressed ? 0.95 : (isSelected ? 1.02 : 1.0))
        }
        .buttonStyle(PlayResultButtonStyle(isPressed: $isPressed))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(result.accessibilityLabel))
        .accessibilityHint(Text("Selects this play result and asks for confirmation"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PlayResultButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

// MARK: - Section Header

struct PlayResultSectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Divider

struct PlayResultDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.2), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.vertical, 2)
    }
}

// MARK: - Custom Mode Picker

struct PlayResultModePicker: View {
    @Binding var selection: AthleteRole

    var body: some View {
        HStack(spacing: 0) {
            ModeButton(
                title: "Batter",
                icon: "figure.baseball",
                isSelected: selection == .batter
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selection = .batter
                }
                Haptics.light()
            }

            ModeButton(
                title: "Pitcher",
                icon: "figure.cricket",
                isSelected: selection == .pitcher
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selection = .pitcher
                }
                Haptics.light()
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
    }

    struct ModeButton: View {
        let title: String
        let icon: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))

                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LinearGradient.primaryButton)
                                .shadow(color: Color.brandNavy.opacity(0.4), radius: 8, x: 0, y: 2)
                        }
                    }
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Pitch Type Button

struct PitchTypeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LinearGradient(colors: [.purple, .purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .shadow(color: .purple.opacity(0.4), radius: 8, x: 0, y: 2)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Premium Action Button

struct PlayResultActionButton: View {
    let title: String
    let icon: String
    let style: ActionStyle
    let action: () -> Void

    enum ActionStyle {
        case primary
        case secondary
    }

    @State private var isPressed = false

    private var shadowColor: Color {
        switch style {
        case .primary: return .brandNavy.opacity(0.4)
        case .secondary: return .clear
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient.primaryButton)
        case .secondary:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.15))
        }
    }

    var body: some View {
        Button(action: {
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))

                Text(title)
                    .font(.body.weight(.semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(backgroundView)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient.glassBorder,
                        lineWidth: 1
                    )
            )
            .shadow(color: shadowColor, radius: 8, x: 0, y: 4)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(ActionButtonStyle(isPressed: $isPressed))
    }

    struct ActionButtonStyle: ButtonStyle {
        @Binding var isPressed: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .onChange(of: configuration.isPressed) { _, newValue in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        isPressed = newValue
                    }
                }
        }
    }
}
