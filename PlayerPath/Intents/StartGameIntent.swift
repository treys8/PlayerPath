//
//  StartGameIntent.swift
//  PlayerPath
//
//  Siri/Shortcuts/Spotlight: "Start a game or round". An open-app intent that
//  hands off to the existing create-game/round screen for the chosen profile.
//  perform() does NO mutation — it resolves a profile id and routes through
//  IntentNavigationBridge; the in-app screen (and GameService) own all writes.
//

import AppIntents

struct StartGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Game or Round"
    static let description = IntentDescription("Open the screen to start a new game or round.")

    // Opening the create screen needs the foreground; perform() only hands off.
    static let openAppWhenRun = true

    @Parameter(title: "Profile")
    var profile: AthleteAppEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        var resolvedID = profile?.id

        // No explicit profile: default to the active one, but prompt when the
        // active person has ≥2 linked sport profiles (e.g. baseball AND golf),
        // so "start my game" lands on the sport the user means.
        if resolvedID == nil, let active = IntentSupport.resolveActiveAthlete() {
            let siblings = IntentSupport.siblingProfiles(of: active)
            if siblings.count > 1 {
                let options = siblings.map { AthleteAppEntity($0) }
                let chosen = try await $profile.requestDisambiguation(
                    among: options,
                    dialog: "Which profile?"
                )
                resolvedID = chosen.id
            } else {
                resolvedID = active.id
            }
        }

        IntentNavigationBridge.shared.requestStartGame(athleteID: resolvedID)
        return .result()
    }
}
