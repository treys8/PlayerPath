import Foundation
import SwiftUI

// Centralized, typed helpers for app-wide notifications.
// This is additive and optional: existing NotificationCenter posts still work.

enum AppEvent {
    case switchTab(MainTab)
    case presentVideoRecorder
    case showAthleteSelection
    case switchAthlete(Athlete)
    case recordedHitResult([String: Any])
    case videosManageOwnControls(Bool)
    case presentAddGame(Any?)
    case presentFullscreenVideo(Any?)
    case reactivateGame(Any?)
    case presentSeasons(Athlete)
    case presentCoaches(Athlete)
    case presentProfileEditor(User)
}

extension Notification.Name {
    static let switchTab = Notification.Name("switchTab")
    static let presentVideoRecorder = Notification.Name("presentVideoRecorder")
    static let showAthleteSelection = Notification.Name("showAthleteSelection")
    static let switchAthlete = Notification.Name("switchAthlete")
    static let recordedHitResult = Notification.Name("recordedHitResult")
    static let videosManageOwnControls = Notification.Name("videosManageOwnControls")
    static let presentAddGame = Notification.Name("presentAddGame")
    static let presentFullscreenVideo = Notification.Name("presentFullscreenVideo")
    static let reactivateGame = Notification.Name("reactivateGame")
    static let presentSeasons = Notification.Name("presentSeasons")
    static let presentCoaches = Notification.Name("presentCoaches")
    static let presentProfileEditor = Notification.Name("presentProfileEditor")
    static let showPaywall = Notification.Name("showPaywall")
}

@inline(__always)
func post(_ event: AppEvent) {
    switch event {
    case .switchTab(let tab):
        NotificationCenter.default.post(name: .switchTab, object: tab.rawValue)
    case .presentVideoRecorder:
        NotificationCenter.default.post(name: .presentVideoRecorder, object: nil)
    case .showAthleteSelection:
        NotificationCenter.default.post(name: .showAthleteSelection, object: nil)
    case .switchAthlete(let athlete):
        NotificationCenter.default.post(name: .switchAthlete, object: athlete)
    case .recordedHitResult(let info):
        NotificationCenter.default.post(name: .recordedHitResult, object: info)
    case .videosManageOwnControls(let flag):
        NotificationCenter.default.post(name: .videosManageOwnControls, object: flag)
    case .presentAddGame(let payload):
        NotificationCenter.default.post(name: .presentAddGame, object: payload)
    case .presentFullscreenVideo(let payload):
        NotificationCenter.default.post(name: .presentFullscreenVideo, object: payload)
    case .reactivateGame(let payload):
        NotificationCenter.default.post(name: .reactivateGame, object: payload)
    case .presentSeasons(let athlete):
        NotificationCenter.default.post(name: .presentSeasons, object: athlete)
    case .presentCoaches(let athlete):
        NotificationCenter.default.post(name: .presentCoaches, object: athlete)
    case .presentProfileEditor(let user):
        NotificationCenter.default.post(name: .presentProfileEditor, object: user)
    }
}

// Optional: typed subscribers can be added later if desired.
