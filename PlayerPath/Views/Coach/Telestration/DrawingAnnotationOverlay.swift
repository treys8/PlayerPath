//
//  DrawingAnnotationOverlay.swift
//  PlayerPath
//
//  Read-only display of a saved telestration drawing overlaid
//  on the video player. Used when viewing drawing annotations.
//

import SwiftUI
import PencilKit

struct DrawingAnnotationOverlay: View {
    let drawingData: Data
    let videoAspectRatio: CGFloat
    /// Canvas size (points) the drawing was captured on. When provided, strokes are
    /// rendered in that coordinate space and scaled uniformly to fit the video area.
    /// When nil (legacy annotations), falls back to stroke-bounds rendering.
    let canvasSize: CGSize?
    /// Geometric shapes placed alongside the ink strokes. Empty for annotations
    /// authored before the shape-tools feature.
    var shapes: [TelestrationShape] = []
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var renderedImage: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let containerSize = geometry.size
            let renderSize = fitSize(
                aspectRatio: videoAspectRatio,
                in: containerSize
            )

            ZStack {
                // Semi-transparent backdrop
                Color.black.opacity(0.2)
                    .onTapGesture { onDismiss() }

                // Rendered drawing (cached) — placeholder spinner while the
                // off-main render is in flight, so dense drawings don't hitch
                // the first frame of the overlay.
                if let image = renderedImage {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: renderSize.width, height: renderSize.height)
                        .position(x: containerSize.width / 2, y: containerSize.height / 2)
                        .allowsHitTesting(false)
                } else {
                    ProgressView()
                        .tint(.white)
                        .position(x: containerSize.width / 2, y: containerSize.height / 2)
                }

                // Geometric shapes (arrows, lines, circles, rects) layered above
                // the ink image. Empty for legacy annotations — no layout impact.
                if !shapes.isEmpty {
                    TelestrationShapeLayer(shapes: shapes, canvasSize: renderSize)
                        .frame(width: renderSize.width, height: renderSize.height)
                        .position(x: containerSize.width / 2, y: containerSize.height / 2)
                        .allowsHitTesting(false)
                }

                // Dismiss hint
                VStack {
                    Spacer()
                    Text("Tap to dismiss")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Capsule().fill(Color.black.opacity(0.4)))
                        .padding(.bottom, 16)
                }
            }
        }
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            // Capture inputs locally so the detached task reads no SwiftUI state.
            // When the parent nils out `activeDrawingOverlay`, this view is
            // destroyed; any late MainActor.run write to dead State is a no-op.
            let data = drawingData
            let size = canvasSize
            let scale = displayScale
            Task.detached(priority: .userInitiated) {
                let image = Self.renderDrawing(data: data, canvasSize: size, scale: scale)
                await MainActor.run {
                    renderedImage = image
                    withAnimation(.easeIn(duration: 0.25)) {
                        isVisible = true
                    }
                }
            }
        }
    }

    /// Renders the drawing off the main thread. When canvasSize is provided,
    /// renders the full canvas rect so stroke positions are preserved relative
    /// to the video frame. Falls back to stroke bounds for legacy annotations.
    /// `nonisolated` so the detached render task can call it without an actor hop.
    private nonisolated static func renderDrawing(data: Data, canvasSize: CGSize?, scale: CGFloat) -> UIImage? {
        guard let pkDrawing = try? PKDrawing(data: data) else { return nil }
        if let canvasSize, canvasSize.width > 0, canvasSize.height > 0 {
            let rect = CGRect(origin: .zero, size: canvasSize)
            return pkDrawing.image(from: rect, scale: scale)
        }
        let drawingBounds = pkDrawing.bounds
        guard !drawingBounds.isEmpty else { return nil }
        let padded = drawingBounds.insetBy(dx: -8, dy: -8)
        return pkDrawing.image(from: padded, scale: scale)
    }

    private func fitSize(aspectRatio: CGFloat, in container: CGSize) -> CGSize {
        guard aspectRatio > 0, container.width > 0, container.height > 0 else {
            return container
        }
        let containerRatio = container.width / container.height
        if containerRatio > aspectRatio {
            return CGSize(width: container.height * aspectRatio, height: container.height)
        } else {
            return CGSize(width: container.width, height: container.width / aspectRatio)
        }
    }
}
