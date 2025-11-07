import Foundation
import SwiftUI

/// Strongly-typed helpers for posting/consuming common video-related app events.
/// Wraps NotificationCenter posting to avoid stringly-typed mistakes.
enum VideosEventBus {
    /// Ask Videos module to present its recorder UI.
    static func presentRecorder() {
        NotificationCenter.default.post(name: .presentVideoRecorder, object: nil)
    }

    /// Ask Videos module (or a global handler) to present a given clip fullscreen.
    /// - Parameter clip: The video clip to show.
    static func presentFullscreen(for clip: VideoClip) {
        NotificationCenter.default.post(name: .presentFullscreenVideo, object: clip)
    }

    /// Toggle whether the Videos tab manages its own Record/Upload controls.
    /// - Parameter managesControls: true when Videos owns controls; false to show global floating button.
    static func setVideosManageOwnControls(_ managesControls: Bool) {
        NotificationCenter.default.post(name: .videosManageOwnControls, object: managesControls)
    }
}
