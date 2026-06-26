//
//  ReelOverlayRenderer.swift
//  PlayerPath
//
//  Builds the Core Animation layer tree that bakes a name/caption overlay into a
//  stitched reel via AVVideoCompositionCoreAnimationTool. The only consumer is
//  VideoStitchingService's social-export (non-default) branch.
//
//  IMPORTANT: CALayers must be built on the MAIN thread or the export yields black
//  frames — hence `@MainActor`. The whole stitch runs main-actor-isolated (this build
//  is MainActor-by-default), so calling this synchronously from `stitch` is correct;
//  do NOT move layer construction into a detached task.
//
//  Coordinate space is bottom-left origin (Core Video), so the overlay is anchored to
//  the bottom: name sits just above the caption.
//

import AVFoundation
import UIKit
import QuartzCore

@MainActor
enum ReelOverlayRenderer {
    /// Returns a Core Animation tool that composites the video into `videoLayer` and
    /// draws the name/caption layers on top, inside a `renderSize` canvas (opaque-black
    /// background for 9:16 so letterbox bars are solid).
    static func makeAnimationTool(renderSize: CGSize, options: ReelExportOptions) -> AVVideoCompositionCoreAnimationTool {
        let bounds = CGRect(origin: .zero, size: renderSize)

        let videoLayer = CALayer()
        videoLayer.frame = bounds

        let parentLayer = CALayer()
        parentLayer.frame = bounds
        // Parent-layer half of the 9:16 background (the composition instruction is the
        // other half). Opaque black so the bars never show through.
        if options.aspect == .vertical9x16 {
            parentLayer.backgroundColor = UIColor.black.cgColor
        }
        parentLayer.addSublayer(videoLayer)

        let hInset = renderSize.width * ReelOverlayTextStyle.horizontalInsetFraction
        let bottomInset = renderSize.height * ReelOverlayTextStyle.bottomInsetFraction
        let lineGap = renderSize.height * 0.012
        let maxTextWidth = max(0, renderSize.width - hInset * 2)

        // Bottom-left origin: build the lower (caption) line first, then the name above.
        var cursorY = bottomInset

        if let caption = options.resolvedCaption {
            let font = ReelOverlayTextStyle.captionFont(canvasHeight: renderSize.height)
            let height = ceil(font.lineHeight)
            parentLayer.addSublayer(
                makeTextLayer(caption, font: font,
                              frame: CGRect(x: hInset, y: cursorY, width: maxTextWidth, height: height))
            )
            cursorY += height + lineGap
        }

        if let name = options.resolvedName {
            let font = ReelOverlayTextStyle.nameFont(canvasHeight: renderSize.height)
            let height = ceil(font.lineHeight)
            parentLayer.addSublayer(
                makeTextLayer(name, font: font,
                              frame: CGRect(x: hInset, y: cursorY, width: maxTextWidth, height: height))
            )
        }

        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
    }

    private static func makeTextLayer(_ text: String, font: UIFont, frame: CGRect) -> CATextLayer {
        let layer = CATextLayer()
        // NSAttributedString.foregroundColor on iOS expects a UIColor (a CGColor here is
        // silently ignored and the text renders black — illegible over video).
        layer.string = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: ReelOverlayTextStyle.textColor
        ])
        layer.frame = frame
        layer.alignmentMode = .left
        // Single line + ellipsis: the frame is one line tall, so wrapping would clip.
        layer.isWrapped = false
        layer.truncationMode = .end
        // Crisp glyphs (CATextLayer defaults to 1.0 and looks blurry when oversampled).
        layer.contentsScale = ReelOverlayTextStyle.renderScale
        // Legibility over bright footage.
        layer.shadowColor = ReelOverlayTextStyle.shadowColor.cgColor
        layer.shadowOpacity = ReelOverlayTextStyle.shadowOpacity
        layer.shadowRadius = ReelOverlayTextStyle.shadowRadius
        layer.shadowOffset = CGSize(width: 0, height: 1)
        return layer
    }
}
