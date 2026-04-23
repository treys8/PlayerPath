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
    let onSave: (PKDrawing, [TelestrationShape], Double, CGSize) async -> Bool
    let onCancel: () -> Void
    /// Freeze-frame rendered behind the canvas when the overlay is presented
    /// full-screen (e.g. from ClipReviewSheet). Nil when another video view
    /// is already visible behind the overlay (e.g. CoachVideoPlayerView).
    var frameImage: UIImage? = nil

    @State private var drawing = PKDrawing()
    @State private var shapes: [TelestrationShape] = []
    @State private var toolMode: TelestrationToolMode = .freehand
    @State private var selectedColor: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var canvasSize: CGSize = .zero
    @State private var showingCancelConfirm = false

    /// Insertion-order history of every user-added element (ink strokes + shapes).
    /// Undo pops the last entry; redo re-adds from `redoStack`. Any fresh user
    /// edit clears `redoStack` — standard undo/redo semantics.
    @State private var undoLog: [UndoKind] = []
    @State private var redoStack: [RedoEntry] = []

    private enum UndoKind: Equatable { case stroke, shape }

    private enum RedoEntry {
        case stroke(PKStroke)
        case shape(TelestrationShape)
    }

    private var maxStrokes: Int { TelestrationConstants.maxStrokes }
    private var maxShapes: Int { TelestrationConstants.maxShapes }

    /// Combined ink-strokes + placed shapes. Gates the overall element cap.
    private var elementCount: Int {
        drawing.strokes.count + shapes.count
    }

    private var currentTool: PKTool {
        PKInkingTool(.pen, color: UIColor(selectedColor), width: lineWidth)
    }

    private var hasAnyContent: Bool {
        !drawing.strokes.isEmpty || !shapes.isEmpty
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
                    toolMode: $toolMode,
                    elementCount: elementCount,
                    shapeCount: shapes.count,
                    canUndo: !undoLog.isEmpty,
                    canRedo: !redoStack.isEmpty,
                    onUndo: undo,
                    onRedo: redo,
                    onClear: clearAll,
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
                            // Ink canvas only accepts input when freehand is selected;
                            // shape tools route touches to the creation overlay above.
                            isEnabled: !isSaving
                                && elementCount < maxStrokes
                                && toolMode == .freehand
                        )
                        .frame(width: fittedCanvas.width, height: fittedCanvas.height)

                        // Placed shapes — always visible, inert. The gesture overlay
                        // stacks above and handles creation when a shape tool is active.
                        TelestrationShapeLayer(shapes: shapes, canvasSize: fittedCanvas)
                            .allowsHitTesting(false)

                        if let shapeKind = toolMode.shapeKind, !isSaving {
                            ShapeCreationOverlay(
                                kind: shapeKind,
                                canvasSize: fittedCanvas,
                                color: selectedColor,
                                lineWidth: lineWidth,
                                onCommit: { shape in
                                    guard shapes.count < maxShapes,
                                          elementCount < maxStrokes else { return }
                                    shapes.append(shape)
                                    undoLog.append(.shape)
                                    redoStack.removeAll()
                                    Haptics.light()
                                }
                            )
                        }
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
        // Detect user-added ink strokes by comparing actual count to the number
        // of .stroke entries we've logged. Our own undo/redo paths maintain the
        // log in lockstep with the drawing mutation, so by the time onChange
        // fires both values are aligned and this branch is a no-op.
        .onChange(of: drawing.strokes.count) { _, newCount in
            let loggedStrokeCount = undoLog.reduce(into: 0) { acc, kind in
                if kind == .stroke { acc += 1 }
            }
            if newCount > loggedStrokeCount {
                for _ in 0..<(newCount - loggedStrokeCount) {
                    undoLog.append(.stroke)
                }
                redoStack.removeAll()
            }
        }
    }

    /// Undo pops the most recently added element — whichever of (stroke, shape)
    /// was added last. Preserves true insertion order thanks to `undoLog`, so
    /// an undo sequence exactly reverses the user's edits.
    private func undo() {
        guard let last = undoLog.popLast() else { return }
        switch last {
        case .stroke:
            guard let popped = drawing.strokes.last else { return }
            var strokes = drawing.strokes
            strokes.removeLast()
            drawing = PKDrawing(strokes: strokes)
            redoStack.append(.stroke(popped))
        case .shape:
            guard let popped = shapes.last else { return }
            shapes.removeLast()
            redoStack.append(.shape(popped))
        }
        Haptics.light()
    }

    /// Re-applies the last undone element. Cleared whenever the user performs
    /// a fresh edit (matches standard undo/redo semantics).
    private func redo() {
        guard let last = redoStack.popLast() else { return }
        switch last {
        case .stroke(let stroke):
            var strokes = drawing.strokes
            strokes.append(stroke)
            drawing = PKDrawing(strokes: strokes)
            undoLog.append(.stroke)
        case .shape(let shape):
            shapes.append(shape)
            undoLog.append(.shape)
        }
        Haptics.light()
    }

    private func clearAll() {
        drawing = PKDrawing()
        shapes = []
        undoLog.removeAll()
        redoStack.removeAll()
    }

    private func save() {
        guard hasAnyContent else { return }
        isSaving = true
        let capturedSize = canvasSize
        let capturedShapes = shapes
        Task {
            let success = await onSave(drawing, capturedShapes, timestamp, capturedSize)
            isSaving = false
            if !success {
                saveError = "Drawing could not be saved. Try simplifying it."
            }
        }
    }

    private func handleCancel() {
        if !hasAnyContent {
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
