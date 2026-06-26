//
//  PlayerPathShortcuts.swift
//  PlayerPath
//
//  Declares the app's Siri/Shortcuts/Spotlight phrases. Every phrase MUST
//  include \(.applicationName). Keep phrases stable once shipped — Siri
//  donation/relevance keys off them.
//

import AppIntents

struct PlayerPathShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordClipIntent(),
            phrases: [
                "Record a clip in \(.applicationName)",
                "Record a video in \(.applicationName)",
                "\(.applicationName) record a clip"
            ],
            shortTitle: "Record Clip",
            systemImageName: "video.badge.plus"
        )
        AppShortcut(
            intent: StartGameIntent(),
            phrases: [
                "Start a game in \(.applicationName)",
                "Start a round in \(.applicationName)",
                "Start my game in \(.applicationName)",
                "\(.applicationName) start a game"
            ],
            shortTitle: "Start Game",
            systemImageName: "play.circle.fill"
        )
    }
}
