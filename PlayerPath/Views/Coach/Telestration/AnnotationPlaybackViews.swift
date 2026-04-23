//
//  AnnotationPlaybackViews.swift
//  PlayerPath
//
//  Shared playback-side annotation views used by both CoachVideoPlayerView
//  (coach / athlete-viewing-shared-folder) and VideoPlayerView (athlete's own
//  Videos tab, for clips saved from a coach's shared folder).
//

import SwiftUI

/// Wraps a PKDrawing's base64 Data, the canvas size it was captured on, and
/// any geometric shapes placed alongside the ink strokes. Used for presentation
/// by `DrawingAnnotationOverlay`.
struct ActiveDrawingOverlay: Equatable {
    let data: Data
    let canvasSize: CGSize?
    let shapes: [TelestrationShape]

    init(data: Data, canvasSize: CGSize?, shapes: [TelestrationShape] = []) {
        self.data = data
        self.canvasSize = canvasSize
        self.shapes = shapes
    }
}

/// Timeline marker strip — one thin rectangle per annotation, positioned along
/// the bottom of the video by timestamp. When `onTapDrawing` is provided, the
/// drawing markers become tappable; otherwise the whole overlay is inert.
struct AnnotationMarkersOverlay: View {
    let annotations: [VideoAnnotation]
    let duration: Double
    /// When non-nil, drawing-type markers expose a tappable hit-region that
    /// invokes this callback. Leave nil for inert visual-only markers (the
    /// default in `CoachVideoPlayerView`, where drawings open from the Notes
    /// tab instead of from the timeline).
    var onTapDrawing: ((VideoAnnotation) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                ForEach(annotations) { annotation in
                    let x = (CGFloat(annotation.timestamp) / CGFloat(duration)) * geometry.size.width
                    let color: Color = annotation.isCoachComment ? Color.brandNavy : Color.orange

                    if let onTapDrawing, annotation.type == "drawing" {
                        // Interactive marker: expand hit region with a padded
                        // clear rect so 3pt-wide bars are actually tappable.
                        Button {
                            onTapDrawing(annotation)
                        } label: {
                            ZStack(alignment: .center) {
                                Color.clear.frame(width: 20, height: 30)
                                Rectangle()
                                    .fill(color)
                                    .frame(width: 3, height: 20)
                                    .shadow(color: .black.opacity(0.5), radius: 2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: x - 10)
                    } else {
                        Rectangle()
                            .fill(color)
                            .frame(width: 3, height: 20)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .offset(x: x)
                            // Non-drawing markers stay inert so a stray tap
                            // on a narrow bar doesn't swallow a scrubber drag.
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .allowsHitTesting(onTapDrawing != nil)
    }
}
