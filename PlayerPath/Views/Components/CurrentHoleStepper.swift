//
//  CurrentHoleStepper.swift
//  PlayerPath
//
//  Compact "current hole" control for casual golf recording (no live, scored
//  round). Bound to GolfCaptureContext: sets the hole the next clip is stamped
//  with, or "Range" (nil) for a range session. Shown as an overlay pill on the
//  camera recorder for golf athletes recording without a game/practice context.
//

import SwiftUI

struct CurrentHoleStepper: View {
    private let context = GolfCaptureContext.shared

    private var atRange: Bool { context.currentHole == nil }
    private var atMax: Bool { context.currentHole == context.holeCount }

    var body: some View {
        HStack(spacing: 16) {
            Button {
                Haptics.light()
                context.decrement()
            } label: {
                Image(systemName: "minus")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
            }
            .disabled(atRange)
            .opacity(atRange ? 0.35 : 1)

            VStack(spacing: 1) {
                Text(atRange ? "Range" : "Hole \(context.currentHole!)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text(atRange ? "no hole tag" : "tags this hole")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(minWidth: 88)

            Button {
                Haptics.light()
                context.increment()
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
            }
            .disabled(atMax)
            .opacity(atMax ? 0.35 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(atRange ? "Range session, no hole" : "Hole \(context.currentHole!)")
        .accessibilityHint("Sets the hole the next clip is tagged with")
    }
}
