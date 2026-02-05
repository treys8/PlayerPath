//
//  RoleSelectionButton.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct RoleSelectionButton: View {
    let role: UserRole
    let isSelected: Bool
    let icon: String
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                // Icon with background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isSelected
                                    ? [Color.white.opacity(0.2), Color.white.opacity(0.1)]
                                    : [.blue.opacity(0.12), .blue.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(
                            isSelected
                                ? AnyShapeStyle(Color.white)
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                }

                VStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? .white : .primary)

                    Text(description)
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [.blue, .blue.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color(.systemBackground), Color(.systemBackground)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .shadow(
                        color: isSelected ? .blue.opacity(0.3) : .black.opacity(0.06),
                        radius: isSelected ? 10 : 4,
                        x: 0,
                        y: isSelected ? 5 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.clear : Color(.systemGray4),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityLabel("\(title): \(description)")
        .accessibilityHint(isSelected ? "Selected" : "Tap to select \(title)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    HStack(spacing: 12) {
        RoleSelectionButton(
            role: .athlete,
            isSelected: true,
            icon: "figure.baseball",
            title: "Athlete",
            description: "Track my progress"
        ) {}

        RoleSelectionButton(
            role: .coach,
            isSelected: false,
            icon: "person.2.fill",
            title: "Coach",
            description: "Work with athletes"
        ) {}
    }
    .padding()
}
