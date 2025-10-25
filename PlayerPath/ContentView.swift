//
//  ContentView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData

// This is now mainly used as a fallback or for previews
// The main app flow starts with MainAppView
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        MainAppView()
    }
}

#Preview {
    ContentView()
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
        ], inMemory: true)
}
