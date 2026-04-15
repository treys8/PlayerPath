import Foundation
import AVFoundation
import UIKit

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
                return .portrait
            }
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let applied = natural.applying(transform)
            let w = abs(applied.width)
            let h = abs(applied.height)
            if abs(w - h) < 1 { return .square }
            return w > h ? .landscape : .portrait
        } catch {
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
            let current = UIDevice.current.orientation
            switch current {
            case .landscapeLeft:
                mask = .landscape
                target = .landscapeLeft
            case .landscapeRight:
                mask = .landscape
                target = .landscapeRight
            default:
                mask = .landscape
                target = .landscapeRight
            }
        }
        PlayerPathAppDelegate.orientationLock = mask
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: target))
        }
    }

    static func restore() {
        PlayerPathAppDelegate.orientationLock = .allButUpsideDown
    }
}
