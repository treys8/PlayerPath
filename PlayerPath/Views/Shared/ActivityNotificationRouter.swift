//
//  ActivityNotificationRouter.swift
//  PlayerPath
//
//  Shared routing for activity notifications. Called from the in-app banner
//  and the notification inbox so both surfaces navigate identically.
//

import Foundation
import SwiftUI

enum ActivityNotificationRouter {

    /// Posts NotificationCenter events to navigate to the destination for
    /// `notification`. Role-scoped: coaches route to CoachTabView destinations,
    /// athletes route to MainTabView destinations.
    @MainActor
    static func route(_ notification: ActivityNotification, isCoach: Bool) {
        switch notification.type {
        case .coachComment, .newVideo:
            let folderID = notification.folderID
                ?? (notification.targetType == .folder ? notification.targetID : nil)
            // When the notification targets a specific video, forward its ID so
            // the folder view can scroll to and highlight that clip.
            let videoID: String? = (notification.targetType == .video) ? notification.targetID : nil
            if let folderID {
                let userInfo: [AnyHashable: Any]? = videoID.map { ["videoID": $0] }
                if isCoach {
                    NotificationCenter.default.post(name: .navigateToCoachFolder, object: folderID, userInfo: userInfo)
                } else {
                    NotificationCenter.default.post(name: .navigateToSharedFolder, object: folderID, userInfo: userInfo)
                }
            } else {
                postSwitchTab(.more)
            }
        case .invitationAccepted:
            if isCoach, let folderID = notification.targetID, notification.targetType == .folder {
                NotificationCenter.default.post(name: .navigateToCoachFolder, object: folderID)
            } else {
                postSwitchTab(.more)
            }
        case .invitationReceived:
            if isCoach {
                NotificationCenter.default.post(name: .openCoachInvitations, object: nil)
            } else {
                postSwitchTab(.more)
            }
        case .accessRevoked, .accessLapsed:
            if isCoach {
                NotificationCenter.default.post(name: .switchCoachTab, object: CoachTab.athletes.rawValue)
            }
        case .uploadFailed:
            let folderID = notification.folderID
                ?? (notification.targetType == .folder ? notification.targetID : nil)
            if isCoach, let folderID {
                NotificationCenter.default.post(name: .navigateToCoachFolder, object: folderID)
            } else if isCoach {
                NotificationCenter.default.post(name: .switchCoachTab, object: CoachTab.athletes.rawValue)
            } else {
                postSwitchTab(.more)
            }
        }
    }

    static func iconName(for type: ActivityNotification.NotificationType) -> String {
        switch type {
        case .newVideo:           return "video.fill"
        case .coachComment:       return "bubble.left.fill"
        case .invitationReceived: return "envelope.fill"
        case .invitationAccepted: return "checkmark.circle.fill"
        case .accessRevoked:      return "minus.circle.fill"
        case .accessLapsed:       return "exclamationmark.triangle.fill"
        case .uploadFailed:       return "exclamationmark.arrow.triangle.2.circlepath"
        }
    }

    static func iconColor(for type: ActivityNotification.NotificationType) -> Color {
        switch type {
        case .newVideo:           return .brandNavy
        case .coachComment:       return .green
        case .invitationReceived: return .indigo
        case .invitationAccepted: return .green
        case .accessRevoked:      return .orange
        case .accessLapsed:       return .yellow
        case .uploadFailed:       return .red
        }
    }
}
