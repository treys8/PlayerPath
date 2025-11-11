// This file is no longer needed - the main app flow now starts with PlayerPathRootView
// Keep this file for backward compatibility but redirect to the new flow

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        PlayerPathMainView()
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
            GameStatistics.self,
            OnboardingProgress.self
        ], inMemory: true)
}
