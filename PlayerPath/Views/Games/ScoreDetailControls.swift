//
//  ScoreDetailControls.swift
//  PlayerPath
//
//  Optional detailed per-hole inputs (SchemaV29), shared by GolfScorecardView
//  and ScoreHoleSheet so the two scoring surfaces stay identical. Only shown
//  when the user has "track detailed stats" enabled.
//

import SwiftUI

/// Tri-state Hit / Miss / not-tracked control for fairway-in-regulation and
/// green-in-regulation. `nil` = not tracked (excluded from stat denominators);
/// `true` = hit; `false` = missed. The tri-state matters: a *missed* fairway
/// counts toward FIR%, an *untracked* one doesn't.
struct HitMissControl: View {
    let label: String
    let systemImage: String
    @Binding var value: Bool?

    var body: some View {
        HStack {
            Label(label, systemImage: systemImage)
                .font(.bodyMedium)
            Spacer()
            HStack(spacing: 6) {
                pill("—", isOn: value == nil, tint: .secondary) { value = nil }
                pill("Hit", isOn: value == true, tint: .green) { value = true }
                pill("Miss", isOn: value == false, tint: .red) { value = false }
            }
        }
    }

    private func pill(_ text: String, isOn: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(text)
                .font(.labelMedium)
                .fontWeight(isOn ? .bold : .regular)
                .foregroundColor(isOn ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: .cornerMedium)
                        .fill(isOn ? tint : Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}
