//
//  IntentNavigationBridge.swift
//  PlayerPath
//
//  Carries a pending App-Intent navigation request from an AppIntent's
//  perform() to the authenticated root view (UserMainFlow), which replays it
//  onto the existing NotificationCenter routes (.presentVideoRecorder /
//  .presentAddGame / .switchAthlete). Mirrors QuickActionsManager so the
//  hand-off is cold-launch-safe: UserMainFlow consumes `pending` both in
//  .task (the initial value, which .onChange would miss) and in .onChange
//  (the warm-launch case where the app is already running).
//

import Foundation
import Combine

@MainActor
final class IntentNavigationBridge: ObservableObject {
    static let shared = IntentNavigationBridge()
    private init() {}

    enum PendingAction: Equatable {
        /// Open the recorder for the in-app selected athlete (attaches to its
        /// live game/round if one is in progress).
        case recordClip
        /// Open the create-game/round screen for this profile (nil = active).
        case startGame(athleteID: UUID?)
    }

    @Published var pending: PendingAction?

    func requestRecordClip() {
        pending = .recordClip
    }

    func requestStartGame(athleteID: UUID?) {
        pending = .startGame(athleteID: athleteID)
    }

    /// Returns the pending action and clears it. Idempotent — safe to call from
    /// both .task and .onChange without double-firing the navigation.
    func consume() -> PendingAction? {
        let action = pending
        pending = nil
        return action
    }
}
