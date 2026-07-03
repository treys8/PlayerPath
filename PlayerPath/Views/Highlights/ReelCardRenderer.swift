//
//  ReelCardRenderer.swift
//  PlayerPath
//
//  Renders the reel intro title card (navy background, athlete name + event line +
//  "▶ PlayerPath" wordmark) and encodes it as a short still MP4 that
//  VideoStitchingService prepends as the first composition segment. The only
//  consumer is the social-export (non-default) stitch branch.
//
//  The card is a rasterized bitmap (UIGraphicsImageRenderer) — it never touches
//  AVVideoCompositionCoreAnimationTool, so it is immune to that tool's
//  black-frame footgun. Like ReelOverlayRenderer, image building stays on the
//  main actor (the whole stitch is main-actor-isolated in this build).
//
//  The card image MUST be generated at the reel's final renderSize (post-cap,
//  post-9:16 override) so its composition transform stays identity.
//

import AVFoundation
import UIKit

@MainActor
enum ReelCardRenderer {
    enum CardError: LocalizedError {
        case imageRenderFailed
        case writerSetupFailed
        case encodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .imageRenderFailed: return "Could not render the title card."
            case .writerSetupFailed: return "Could not set up the title card encoder."
            case .encodeFailed(let msg): return msg
            }
        }
    }

    /// Rasterizes the title card at exactly `size` pixels (scale pinned to 1 —
    /// the renderer's default display scale would triple the pixel dimensions).
    static func makeCardImage(size: CGSize, title: String?, subtitle: String?) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            ReelCardStyle.backgroundColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let hInset = size.width * ReelCardStyle.horizontalInsetFraction
            let textRectWidth = max(0, size.width - hInset * 2)

            let titleFont = ReelCardStyle.titleFont(canvasHeight: size.height)
            let subtitleFont = ReelCardStyle.subtitleFont(canvasHeight: size.height)
            let lineGap = size.height * ReelCardStyle.lineGapFraction

            let titleHeight = title == nil ? 0 : ceil(titleFont.lineHeight)
            let subtitleHeight = subtitle == nil ? 0 : ceil(subtitleFont.lineHeight)
            let gap = (title != nil && subtitle != nil) ? lineGap : 0
            let blockHeight = titleHeight + gap + subtitleHeight

            // Name + event line, centered as a block.
            var cursorY = (size.height - blockHeight) / 2
            if let title {
                draw(title, font: titleFont, color: ReelCardStyle.titleColor,
                     in: CGRect(x: hInset, y: cursorY, width: textRectWidth, height: titleHeight))
                cursorY += titleHeight + gap
            }
            if let subtitle {
                draw(subtitle, font: subtitleFont, color: ReelCardStyle.subtitleColor,
                     in: CGRect(x: hInset, y: cursorY, width: textRectWidth, height: subtitleHeight))
            }

            drawWordmark(size: size, textRectWidth: textRectWidth, hInset: hInset)
        }
    }

    /// Bottom-centered "▶ PlayerPath" mark. Isolated so a future logo image swaps in
    /// with a single `image.draw(in:)` here — no layout changes elsewhere.
    private static func drawWordmark(size: CGSize, textRectWidth: CGFloat, hInset: CGFloat) {
        let font = ReelCardStyle.wordmarkFont(canvasHeight: size.height)
        let height = ceil(font.lineHeight)
        let y = size.height - size.height * ReelCardStyle.wordmarkBottomInsetFraction - height
        draw(ReelWatermarkStyle.text, font: font, color: ReelCardStyle.wordmarkColor,
             in: CGRect(x: hInset, y: y, width: textRectWidth, height: height))
    }

    private static func draw(_ text: String, font: UIFont, color: UIColor, in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: text, attributes: [
            .font: font,
            // UIColor, never CGColor — same rule as ReelOverlayRenderer.
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]).draw(in: rect)
    }

    /// Encodes `image` as an H.264 still MP4 of `duration` at `outputURL`. Frames are
    /// appended at a fixed 10 fps — identical frames collapse to a few KB, and the reel's
    /// video composition resamples the still up to the reel frame rate for free.
    static func encodeStillMP4(
        image: UIImage,
        size: CGSize,
        duration: CMTime,
        outputURL: URL
    ) async throws -> URL {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard let cgImage = image.cgImage else { throw CardError.imageRenderFailed }

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else { throw CardError.writerSetupFailed }
        writer.add(input)

        guard let buffer = makePixelBuffer(from: cgImage, width: width, height: height) else {
            throw CardError.writerSetupFailed
        }

        // Unchecked, a failed start leaves the writer .failed and the following
        // startSession raises an uncatchable NSException instead of throwing.
        guard writer.startWriting() else {
            throw CardError.encodeFailed(writer.error?.localizedDescription ?? "Card writer failed to start.")
        }
        writer.startSession(atSourceTime: .zero)

        let frameStep = CMTime(value: 1, timescale: 10)
        var pts: CMTime = .zero
        while pts < duration {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard adaptor.append(buffer, withPresentationTime: pts) else {
                writer.cancelWriting()
                throw CardError.encodeFailed(writer.error?.localizedDescription ?? "Card frame append failed.")
            }
            pts = CMTimeAdd(pts, frameStep)
        }

        input.markAsFinished()
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw CardError.encodeFailed(writer.error?.localizedDescription ?? "Card encode failed.")
        }
        return outputURL
    }

    /// Draws `cgImage` into a fresh pixel buffer. The CGBitmapContext draw lands the
    /// image's top row at the buffer's first row, which is what video frames expect —
    /// text comes out upright without a flip.
    private static func makePixelBuffer(from cgImage: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer)
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
