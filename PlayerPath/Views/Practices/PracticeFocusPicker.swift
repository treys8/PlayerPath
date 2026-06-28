//
//  PracticeFocusPicker.swift
//  PlayerPath
//
//  Multi-select drill/focus chips for a practice ("what did you work on").
//  Sport-aware option list comes from PracticeFocusCatalog; selection is a set
//  of stored rawValues persisted on Practice.drillTypes. Used at create time
//  (AddPracticeView) and when editing a practice (PracticeDetailView).
//

import SwiftUI

struct PracticeFocusPicker: View {
    let sport: Sport
    @Binding var selected: Set<String>

    private var options: [PracticeFocusOption] { PracticeFocusCatalog.options(for: sport) }
    private let columns = [GridItem(.adaptive(minimum: 116), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(options) { option in
                FocusChip(option: option, isSelected: selected.contains(option.rawValue)) {
                    toggle(option.rawValue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ raw: String) {
        if selected.contains(raw) {
            selected.remove(raw)
        } else {
            selected.insert(raw)
        }
        Haptics.light()
    }
}

private struct FocusChip: View {
    let option: PracticeFocusOption
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.ppAccent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: option.icon)
                    .font(.caption)
                Text(option.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(isSelected ? accent.opacity(0.18) : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? accent : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? accent : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
