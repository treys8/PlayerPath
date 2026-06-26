//
//  RecordClipIntent.swift
//  PlayerPath
//
//  Siri/Shortcuts/Spotlight: "Record a clip". An open-app intent — perform()
//  does NO SwiftData/Firestore work; it hands off to the existing recorder
//  route via IntentNavigationBridge (the camera needs the foreground).
//

import AppIntents

struct RecordClipIntent: AppIntent {
    static let title: LocalizedStringResource = "Record a Clip"
    static let description = IntentDescription("Open the camera to record a video clip.")

    // Camera needs the foreground — bring the app forward; perform() only hands off.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentNavigationBridge.shared.requestRecordClip()
        return .result()
    }
}
