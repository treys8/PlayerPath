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
            let device = UIDevice.current.orientation
            switch device {
            case .landscapeLeft:
                mask = .landscape
                target = .landscapeRight
            case .landscapeRight:
                mask = .landscape
                target = .landscapeLeft
            default:
                // Device orientation is unavailable (.unknown when orientation
                // notifications aren't being generated — e.g. on the save screen
                // after the camera VM tore down — or .faceUp/.faceDown when the
                // phone is flat). Fall back to the interface orientation actually
                // drawn on screen. interfaceOrientation is already a
                // UIInterfaceOrientation, so map name-for-name (no device→interface
                // inversion here, unlike the cases above).
                mask = .landscape
                let interface = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }.first?.interfaceOrientation
                switch interface {
                case .landscapeLeft:  target = .landscapeLeft
                case .landscapeRight: target = .landscapeRight
                default:              target = .landscapeRight   // last resort
                }
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
        // Symmetric counterpart to lock(): widening the mask only PERMITS
        // rotation, it does not COMMAND it. iOS won't spontaneously rotate a
        // window back to portrait just because portrait became allowed again —
        // it waits for a physical device-orientation change. So a phone held in
        // landscape leaves the just-revealed portrait-first feed drawn sideways
        // until the user manually rotates. Force a geometry update back to
        // portrait when the UI is currently landscape so the feed snaps upright
        // on dismiss. No-op (and no animation) when already portrait.
        //
        // iPhone ONLY: the portrait-first feed is what justifies snapping
        // upright. iPad supports landscape as a first-class layout, so forcing
        // portrait there would yank an iPad user out of a landscape session they
        // deliberately chose. On iPad we just widen the mask and let the device
        // sensor drive rotation (the old, correct behavior).
        if UIDevice.current.userInterfaceIdiom == .phone,
           let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           scene.interfaceOrientation.isLandscape {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                orientLog.error("restore requestGeometryUpdate failed: \(error.localizedDescription)")
            }
        }
        orientLog.info("restore()")
    }
}
