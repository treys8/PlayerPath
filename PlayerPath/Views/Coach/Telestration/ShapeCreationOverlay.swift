//
//  ShapeCreationOverlay.swift
//  PlayerPath
//
//  Transparent drag-capture view placed above the PencilKit canvas when a
//  shape tool is active. Turns a single drag into one TelestrationShape,
//  rendering a live preview during the drag.
//

import SwiftUI

struct ShapeCreationOverlay: View {
    let kind: TelestrationShapeKind
    let canvasSize: CGSize
    let color: Color
    let lineWidth: CGFloat
    /// Invoked once per completed drag with the resulting shape.
    let onCommit: (TelestrationShape) -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if dragStart == nil {
                                dragStart = clamp(value.startLocation)
                            }
                            dragCurrent = clamp(value.location)
                        }
                        .onEnded { value in
                            defer {
                                dragStart = nil
                                dragCurrent = nil
                            }
                            guard let start = dragStart else { return }
                            let end = clamp(value.location)
                            // Ignore tap-like near-zero drags.
                            let dx = end.x - start.x
                            let dy = end.y - start.y
                            guard sqrt(dx * dx + dy * dy) >= 4 else { return }
                            let shape = TelestrationShape(
                                kind: kind,
                                start: start,
                                end: end,
                                canvasSize: canvasSize,
                                color: color,
                                lineWidth: lineWidth
                            )
                            onCommit(shape)
                        }
                )

            if let start = dragStart, let current = dragCurrent {
                let preview = TelestrationShape(
                    kind: kind,
                    start: start,
                    end: current,
                    canvasSize: canvasSize,
                    color: color,
                    lineWidth: lineWidth
                )
                TelestrationShapeLayer(shapes: [], canvasSize: canvasSize, inFlight: preview)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    /// Keeps drag endpoints inside the canvas so off-canvas drags don't
    /// produce shapes that partially fall outside the video frame on playback.
    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), canvasSize.width),
            y: min(max(point.y, 0), canvasSize.height)
        )
    }
}
