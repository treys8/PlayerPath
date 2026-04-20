import Foundation
import AVFoundation
import UIKit
import os

private let orientLog = Logger(subsystem: "com.playerpath.app", category: "Orientation")

enum VideoOrientation {
    case portrait
    case landscape
    case square

    var isLandscape: Bool { self == .landscape }
}

enum VideoOrientationDetector {
    static func detect(url: URL) async -> VideoOrientation {
        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                orientLog.warning("detect: no video track, defaulting .portrait")
                return .portrait
            }
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let applied = natural.applying(transform)
            let w = abs(applied.width)
            let h = abs(applied.height)
            let result: VideoOrientation
            if abs(w - h) < 1 { result = .square }
            else { result = w > h ? .landscape : .portrait }
            orientLog.info("detect: natural=\(natural.width)x\(natural.height) transform=[a:\(transform.a) b:\(transform.b) c:\(transform.c) d:\(transform.d)] applied=\(w)x\(h) → \(String(describing: result))")
            return result
        } catch {
            orientLog.error("detect failed: \(error.localizedDescription)")
            return .portrait
        }
    }
}

@MainActor
enum OrientationLocker {
    static func lock(for clip: VideoOrientation) {
        let mask: UIInterfaceOrientationMask
        let target: UIInterfaceOrientationMask
        switch clip {
        case .portrait, .square:
            mask = .portrait
            target = .portrait
        case .landscape:
            // UIDeviceOrientation and UIInterfaceOrientation are INVERTED by iOS
            // convention: when the device's left edge is up (UIDevice.landscapeLeft),
            // the interface's right edge is up (UIInterface.landscapeRight), and
            // vice-versa. Using the same-named case here produced a 180° rotation
            // — the "upside down" symptom after recording landscape.
            let current = UIDevice.current.orientation
            switch current {
            case .landscapeLeft:
                mask = .landscape
                target = .landscapeRight
            case .landscapeRight:
                mask = .landscape
                target = .landscapeLeft
            default:
                mask = .landscape
                target = .landscapeRight
            }
        }
        PlayerPathAppDelegate.orientationLock = mask
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { error in
                orientLog.error("requestGeometryUpdate failed: \(error.localizedDescription)")
            }
            orientLog.info("lock(for: \(String(describing: clip))) mask=\(mask.rawValue) target=\(target.rawValue)")
        } else {
            orientLog.warning("lock(for: \(String(describing: clip))): no window scene")
        }
    }

    static func restore() {
        PlayerPathAppDelegate.orientationLock = .allButUpsideDown
        orientLog.info("restore()")
    }
}
