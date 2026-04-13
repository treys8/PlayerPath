//
//  TelestrationOverlayView.swift
//  PlayerPath
//
//  Full telestration experience: transparent PencilKit canvas overlaid
//  on the paused video frame with a drawing toolbar.
//

import SwiftUI
import PencilKit

struct TelestrationOverlayView: View {
    let timestamp: Double
    let videoAspectRatio: CGFloat
    let onSave: (PKDrawing, Double) async -> Bool
    let onCancel: () -> Void

    @State private var drawing = PKDrawing()
    @State private var selectedColor: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var isSaving = false
    @State private var saveError: String?

    private let maxStrokes = 50

    private var strokeCount: Int {
        drawing.strokes.count
    }

    private var currentTool: PKTool {
        PKInkingTool(.pen, color: UIColor(selectedColor), width: lineWidth)
    }

    var body: some View {
        ZStack {
            // Semi-transparent background to dim the video behind the canvas
            Color.black.opacity(0.3)

            VStack(spacing: 0) {
                // Toolbar at top
                TelestrationToolbar(
                    selectedColor: $selectedColor,
                    lineWidth: $lineWidth,
                    strokeCount: strokeCount,
                    onUndo: undo,
                    onClear: { drawing = PKDrawing() },
                    onSave: save,
                    onCancel: onCancel
                )

                // Canvas area — sized to match video aspect ratio
                GeometryReader { geometry in
                    let containerSize = geometry.size
                    let canvasSize = fitSize(
                        aspectRatio: videoAspectRatio,
                        in: containerSize
                    )

                    TelestrationCanvasView(
                        drawing: $drawing,
                        tool: currentTool,
                        isEnabled: !isSaving && strokeCount < maxStrokes
                    )
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .position(x: containerSize.width / 2, y: containerSize.height / 2)
                }
            }
        }
        .overlay(alignment: .center) {
            if isSaving {
                ProgressView("Saving...")
                    .tint(.white)
                    .foregroundColor(.white)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
        .alert("Save Failed", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func undo() {
        guard !drawing.strokes.isEmpty else { return }
        var strokes = drawing.strokes
        strokes.removeLast()
        drawing = PKDrawing(strokes: strokes)
        Haptics.light()
    }

    private func save() {
        guard !drawing.strokes.isEmpty else { return }
        isSaving = true
        Task {
            let success = await onSave(drawing, timestamp)
            isSaving = false
            if !success {
                saveError = "Drawing could not be saved. Try simplifying it."
            }
        }
    }

    /// Calculates the largest size that fits within the container
    /// while preserving the given aspect ratio.
    private func fitSize(aspectRatio: CGFloat, in container: CGSize) -> CGSize {
        guard aspectRatio > 0, container.width > 0, container.height > 0 else {
            return container
        }
        let containerRatio = container.width / container.height
        if containerRatio > aspectRatio {
            // Container is wider — height is the constraint
            return CGSize(width: container.height * aspectRatio, height: container.height)
        } else {
            // Container is taller — width is the constraint
            return CGSize(width: container.width, height: container.width / aspectRatio)
        }
    }
}
