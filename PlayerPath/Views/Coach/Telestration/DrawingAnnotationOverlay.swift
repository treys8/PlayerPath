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

                // Rendered drawing (cached)
                if let image = renderedImage {
                    Image(uiImage: image)
                        .resizable()
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
            renderedImage = renderDrawing()
            withAnimation(.easeIn(duration: 0.25)) {
                isVisible = true
            }
        }
    }

    /// Renders the drawing once on appear. Uses the drawing's own bounds
    /// so strokes aren't clipped; the Image view scales to fit display size.
    private func renderDrawing() -> UIImage? {
        guard let pkDrawing = try? PKDrawing(data: drawingData) else { return nil }
        let drawingBounds = pkDrawing.bounds
        guard !drawingBounds.isEmpty else { return nil }
        let padded = drawingBounds.insetBy(dx: -8, dy: -8)
        return pkDrawing.image(from: padded, scale: displayScale)
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
