//
//  CoachVideoSidebar.swift
//  PlayerPath
//
//  Persistent sidebar for the coach video player on wide layouts
//  (iPad any orientation, iPhone landscape). Wraps the athlete and
//  coach notes plus the annotation panel in a scrollable container.
//

import SwiftUI

struct CoachVideoSidebar<
    AthleteNote: View,
    CoachNote: View,
    AnnotationPanel: View
>: View {
    let showSpeedControl: Bool
    let playbackRate: Double
    let onRateChanged: (Double) -> Void
    @ViewBuilder let athleteNote: AthleteNote
    @ViewBuilder let coachNote: CoachNote
    @ViewBuilder let annotationPanel: AnnotationPanel

    /// Measured natural height of the notes block. Lets the notes region hug
    /// its content instead of reserving a fixed slab, while the cap below keeps
    /// a long coach note from crowding out the annotation panel.
    @State private var notesContentHeight: CGFloat = 240

    var body: some View {
        VStack(spacing: 0) {
            // Speed control pins to the top on iPad (iPhone uses the toolbar
            // button instead).
            if showSpeedControl {
                InlineSpeedControl(
                    selectedRate: playbackRate,
                    onRateChanged: onRateChanged
                )
            }

            // Adaptive split for every wide layout (iPad + iPhone landscape):
            // the notes block (coach note + cues + "Done reviewing") hugs its
            // content so nothing clips, but is capped at ~half the sidebar so a
            // long coach note can't crowd out the annotation panel below, which
            // takes the remainder. Replaces the old fixed-220 cap (iPad, which
            // clipped) and the no-scroll stack (iPhone landscape, which crammed).
            GeometryReader { geo in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            athleteNote
                            coachNote
                        }
                        .background(
                            GeometryReader { inner in
                                Color.clear.preference(
                                    key: NotesHeightKey.self,
                                    value: inner.size.height
                                )
                            }
                        )
                    }
                    .frame(height: min(notesContentHeight, geo.size.height * 0.55))

                    // Annotation panel fills remaining space (has its own internal scroll)
                    annotationPanel
                        .frame(maxHeight: .infinity)
                }
                .onPreferenceChange(NotesHeightKey.self) { notesContentHeight = $0 }
            }
        }
    }
}

/// Reports the intrinsic height of the notes block up to the sidebar's parent.
private struct NotesHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 240
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
