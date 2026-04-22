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
    let onSave: (PKDrawing, Double, CGSize) async -> Bool
    let onCancel: () -> Void
    /// Freeze-frame rendered behind the canvas when the overlay is presented
    /// full-screen (e.g. from ClipReviewSheet). Nil when another video view
    /// is already visible behind the overlay (e.g. CoachVideoPlayerView).
    var frameImage: UIImage? = nil

    @State private var drawing = PKDrawing()
    @State private var selectedColor: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var canvasSize: CGSize = .zero
    @State private var showingCancelConfirm = false

    private var maxStrokes: Int { TelestrationConstants.maxStrokes }

    private var strokeCount: Int {
        drawing.strokes.count
    }

    private var currentTool: PKTool {
        PKInkingTool(.pen, color: UIColor(selectedColor), width: lineWidth)
    }

    var body: some View {
        ZStack {
            // Background: opaque when we own the freeze-frame, else a gentle
            // dim over whatever video view is already visible behind us.
            (frameImage != nil ? Color.black : Color.black.opacity(0.3))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Toolbar at top
                TelestrationToolbar(
                    selectedColor: $selectedColor,
                    lineWidth: $lineWidth,
                    strokeCount: strokeCount,
                    onUndo: undo,
                    onClear: { drawing = PKDrawing() },
                    onSave: save,
                    onCancel: handleCancel
                )

                // Canvas area — sized to match video aspect ratio
                GeometryReader { geometry in
                    let containerSize = geometry.size
                    let fittedCanvas = fitSize(
                        aspectRatio: videoAspectRatio,
                        in: containerSize
                    )

                    ZStack {
                        if let frameImage {
                            Image(uiImage: frameImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: fittedCanvas.width, height: fittedCanvas.height)
                        }
                        TelestrationCanvasView(
                            drawing: $drawing,
                            tool: currentTool,
                            isEnabled: !isSaving && strokeCount < maxStrokes
                        )
                        .frame(width: fittedCanvas.width, height: fittedCanvas.height)
                    }
                    .position(x: containerSize.width / 2, y: containerSize.height / 2)
                    .onAppear { canvasSize = fittedCanvas }
                    .onChange(of: fittedCanvas) { _, newValue in canvasSize = newValue }
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
        .confirmationDialog(
            "Discard drawing?",
            isPresented: $showingCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { onCancel() }
            Button("Keep Drawing", role: .cancel) {}
        } message: {
            Text("Your strokes will be lost.")
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
        let capturedSize = canvasSize
        Task {
            let success = await onSave(drawing, timestamp, capturedSize)
            isSaving = false
            if !success {
                saveError = "Drawing could not be saved. Try simplifying it."
            }
        }
    }

    private func handleCancel() {
        if drawing.strokes.isEmpty {
            onCancel()
        } else {
            showingCancelConfirm = true
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
