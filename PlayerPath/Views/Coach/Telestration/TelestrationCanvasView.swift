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
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // Only push drawing changes from SwiftUI → UIKit when the drawing
        // was reset externally (e.g., undo/clear). Avoid feedback loops by
        // checking if the coordinator is already updating.
        if !context.coordinator.isUpdating && canvas.drawing != drawing {
            canvas.drawing = drawing
        }
        canvas.tool = tool
        canvas.isUserInteractionEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing
        var isUpdating = false

        init(drawing: Binding<PKDrawing>) {
            _drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            isUpdating = true
            drawing = canvasView.drawing
            isUpdating = false
        }
    }
}
