//
//  NewPracticeTypePicker.swift
//  PlayerPath
//
//  Golf-only entry sheet for the Practices "+" action (v6.1 PR3). Lets the
//  athlete pick between a Practice Round (on-course, scorable, gets per-hole
//  scoring and auto-reels) and a Range Session (driving range, no holes,
//  ClubPicker-only). Baseball athletes don't see this sheet — they keep the
//  existing inline Menu in PracticesView.
//

import SwiftUI

struct NewPracticeTypePicker: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (PracticeType) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Pick the kind of practice you're tracking. Practice rounds let you score per hole and surface auto-highlight reels.")
                    .font(.bodyMedium)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                PracticeTypeOption(
                    type: .practiceRound,
                    caption: "Score each hole, attribute clips to the hole, get birdie reels."
                ) {
                    select(.practiceRound)
                }

                PracticeTypeOption(
                    type: .rangeSession,
                    caption: "Driving range. Tag clubs on clips. No hole tracking or scoring."
                ) {
                    select(.rangeSession)
                }

                Spacer()
            }
            .padding(.vertical, 16)
            .navigationTitle("New Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func select(_ type: PracticeType) {
        Haptics.light()
        onSelect(type)
        dismiss()
    }
}

private struct PracticeTypeOption: View {
    let type: PracticeType
    let caption: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: type.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(type.color)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName)
                        .font(.headingMedium)
                        .foregroundColor(.primary)
                    Text(caption)
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .stroke(type.color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}
