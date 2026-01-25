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
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(isSelected ? .white : .blue)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(isSelected ? .white : .primary)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(description)")
        .accessibilityHint(isSelected ? "Selected" : "Tap to select \(title)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
