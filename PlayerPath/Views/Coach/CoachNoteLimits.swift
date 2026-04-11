//
//  CoachNoteLimits.swift
//  PlayerPath
//
//  Shared length constants for plain coach/athlete notes attached to a video.
//

import Foundation

enum CoachNoteLimits {
    /// Hard cap for the plain `notes` / `coachNote` text fields. Matches the
    /// 2000-char clamp used by `ClipCommentService` for timestamped feedback,
    /// scaled down because plain notes are meant to be short cues.
    static let plainNoteCharLimit = 1000
}
