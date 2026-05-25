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

    var body: some View {
        VStack(spacing: 0) {
            if showSpeedControl {
                // iPad: speed control + scrollable notes area (more content to fit)
                InlineSpeedControl(
                    selectedRate: playbackRate,
                    onRateChanged: onRateChanged
                )

                ScrollView {
                    VStack(spacing: 0) {
                        athleteNote
                        coachNote
                    }
                }
                .frame(maxHeight: 220)
            } else {
                // iPhone landscape: notes sit directly in the VStack
                // (no scroll wrapper — preserves original spacing)
                athleteNote
                coachNote
            }

            // Annotation panel fills remaining space (has its own internal scroll)
            annotationPanel
        }
    }
}
