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
        // Assign the initial drawing BEFORE wiring the delegate. Setting
        // `canvas.drawing` fires `canvasViewDrawingDidChange` synchronously; if
        // the delegate were already attached it would write back through the
        // `@Binding` mid-`makeUIView` ("Modifying state during view update").
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
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
            // Programmatic reset (undo/redo/clear/load-saved). Flag it so the
            // delegate callback this assignment triggers doesn't write back
            // through the binding during the update cycle.
            context.coordinator.isApplyingProgrammaticDrawing = true
            canvas.drawing = drawing
            context.coordinator.isApplyingProgrammaticDrawing = false
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
        /// True only while `updateUIView` is assigning `canvas.drawing`
        /// programmatically. Suppresses the binding write-back the assignment's
        /// delegate callback would otherwise make during the SwiftUI update cycle.
        var isApplyingProgrammaticDrawing = false

        init(drawing: Binding<PKDrawing>) {
            _drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Ignore the callback our own programmatic `canvas.drawing =` set
            // triggers — writing the binding there modifies state mid-update.
            guard !isApplyingProgrammaticDrawing else { return }
            // Pencil input — propagate to the binding without touching the
            // version counter, so updateUIView won't push it back and clobber
            // the in-flight stroke.
            drawing = canvasView.drawing
        }
    }
}
