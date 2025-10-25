//
//  PlayerPathApp.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData

@main
struct PlayerPathApp: App {
    var body: some Scene {
        WindowGroup {
            MainAppView()
        }
        .modelContainer(for: [
            User.self,
            Athlete.self,
            Tournament.self,
            Game.self,
            Practice.self,
            PracticeNote.self,
            VideoClip.self,
            PlayResult.self,
            Statistics.self,
            GameStatistics.self
        ], isAutosaveEnabled: true)
    }
}
