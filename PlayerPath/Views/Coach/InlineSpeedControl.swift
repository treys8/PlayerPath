//
//  InlineSpeedControl.swift
//  PlayerPath
//
//  Inline playback speed picker for the iPad coach sidebar.
//  Replaces the toolbar confirmationDialog on wide layouts.
//

import SwiftUI

struct InlineSpeedControl: View {
    let selectedRate: Double
    let onRateChanged: (Double) -> Void

    private let rates: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Speed")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(rates, id: \.self) { rate in
                        Button {
                            Haptics.light()
                            onRateChanged(rate)
                        } label: {
                            Text(rateLabel(rate))
                                .font(.caption)
                                .fontWeight(rate == selectedRate ? .bold : .medium)
                                .monospacedDigit()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    rate == selectedRate
                                        ? Color.brandNavy
                                        : Color(.secondarySystemBackground)
                                )
                                .foregroundColor(
                                    rate == selectedRate ? .white : .primary
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Speed \(rateLabel(rate))")
                        .accessibilityAddTraits(rate == selectedRate ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground).opacity(0.5))
    }

    private func rateLabel(_ rate: Double) -> String {
        if rate == 1.0 { return "1x" }
        if rate < 1.0 { return String(format: "%.2gx", rate) }
        return String(format: "%.4gx", rate)
    }
}
