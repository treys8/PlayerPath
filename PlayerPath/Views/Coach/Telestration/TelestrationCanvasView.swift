//
//  TelestrationCanvasView.swift
//  PlayerPath
//
//  UIViewRepresentable wrapper for PKCanvasView.
//  Supports both Apple Pencil and finger input for drawing
//  on paused video frames during telestration.
//

import SwiftUI
import PencilKit

struct TelestrationCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    /// Monotonic counter bumped by the owner on explicit drawing resets
    /// (undo / redo / clear / load-saved). Pencil input via the delegate must
    /// NOT bump this — those updates flow back through the binding without a
    /// canvas reset. Deep PKDrawing equality on every SwiftUI render was too
    /// expensive on large drawings; the version compare replaces it.
    let drawingVersion: Int
    let tool: PKTool
    let isEnabled: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.tool = tool
        canvas.drawingPolicy = .anyInput
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.isScrollEnabled = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.isUserInteractionEnabled = isEnabled
        canvas.overrideUserInterfaceStyle = .dark
        context.coordinator.lastAppliedVersion = drawingVersion
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if context.coordinator.lastAppliedVersion != drawingVersion {
            canvas.drawing = drawing
            context.coordinator.lastAppliedVersion = drawingVersion
        }
        canvas.tool = tool
        canvas.isUserInteractionEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing
        var lastAppliedVersion: Int = -1

        init(drawing: Binding<PKDrawing>) {
            _drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Pencil input — propagate to the binding without touching the
            // version counter, so updateUIView won't push it back and clobber
            // the in-flight stroke.
            drawing = canvasView.drawing
        }
    }
}
