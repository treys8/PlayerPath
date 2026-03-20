//
//  GameHighlightGroup.swift
//  PlayerPath
//
//  Model representing a group of highlight clips organized by game.
//

import Foundation

// MARK: - Game Highlight Group Model

struct GameHighlightGroup: Identifiable {
    let id: UUID
    let game: Game?
    let clips: [VideoClip]
    var isExpanded: Bool

    var displayTitle: String {
        if let game = game {
            return "vs \(game.opponent)"
        } else {
            return "Practice"
        }
    }

    var displayDate: String {
        if let game = game, let date = game.date {
            return date.formatted(date: .abbreviated, time: .omitted)
        } else if let firstClip = clips.first, let date = firstClip.createdAt {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return ""
    }

    var hitCount: Int {
        clips.count
    }
}
