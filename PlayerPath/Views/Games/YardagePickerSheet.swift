//
//  YardagePickerSheet.swift
//  PlayerPath
//
//  Compact wheel picker for a shot's yards-to-target, opened from the
//  shot-by-shot card's yardage pill. A wheel (not a keyboard) so it never covers
//  the RESULT buttons below the card and stays one-handed on the course. The
//  value is committed to the bound `distance` only on Done; Clear unsets it;
//  swiping the sheet down cancels without changing anything (we mutate a local
//  draft until Done). Seeded at the prior shot's yardage (or a sane default) so
//  it's usually a single flick.
//

import SwiftUI

struct YardagePickerSheet: View {
    @Binding var distance: Int?
    /// Where the wheel starts when no value is set yet (the last recorded
    /// yardage this round, else a middling default).
    let defaultCenter: Int

    @Environment(\.dismiss) private var dismiss
    @State private var value: Int
    /// Wheel ceiling, fixed when the sheet opens. Defaults to 400 — plenty for a
    /// shot's yards-to-pin — but callers entering a HOLE length pass a higher
    /// `maxYardage`, since holes run well past 400 (long par 5s/6s). Always
    /// widened to include an out-of-range seed, so editing a large pre-existing
    /// value round-trips instead of being silently truncated on Done.
    private let upperBound: Int

    init(distance: Binding<Int?>, defaultCenter: Int, maxYardage: Int = 400) {
        self._distance = distance
        self.defaultCenter = defaultCenter
        let seed = max(distance.wrappedValue ?? defaultCenter, 1)
        self._value = State(initialValue: seed)
        self.upperBound = max(maxYardage, seed)
    }

    var body: some View {
        NavigationStack {
            Picker("Yardage", selection: $value) {
                ForEach(1...upperBound, id: \.self) { yd in
                    Text("\(yd) yds").monospacedDigit().tag(yd)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ppDetailBackground()
            .navigationTitle("Yardage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if distance != nil {
                        Button("Clear", role: .destructive) {
                            distance = nil
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.selection()
                        distance = value
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .tint(Theme.golfAccent)
                }
            }
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
    }
}
