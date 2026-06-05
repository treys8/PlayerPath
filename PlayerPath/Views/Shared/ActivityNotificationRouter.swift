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
        case .invitationReceived, .invitationDeclined:
            // Role-agnostic: the mounted tab bar routes to its own invitations
            // surface (coach list vs athlete Home banner). A decline notification
            // goes to the original sender — opening their invitations list is the
            // natural destination.
            NotificationCenter.default.post(name: .openInvitations, object: nil)
        case .accessRevoked, .accessLapsed, .accessRestorePending:
            // Coach taps "athlete wants to reconnect" → their athletes/roster tab
            // (where they upgrade). Athlete-side restore-pending is informational.
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
        case .unknown:
            // A type this build doesn't recognize yet — just open the app; there's
            // no meaningful destination to route to.
            break
        }
    }

    static func iconName(for type: ActivityNotification.NotificationType) -> String {
        switch type {
        case .newVideo:           return "video.fill"
        case .coachComment:       return "bubble.left.fill"
        case .invitationReceived: return "envelope.fill"
        case .invitationAccepted: return "checkmark.circle.fill"
        case .invitationDeclined: return "xmark.circle.fill"
        case .accessRevoked:      return "minus.circle.fill"
        case .accessLapsed:       return "exclamationmark.triangle.fill"
        case .accessRestorePending: return "clock.arrow.circlepath"
        case .uploadFailed:       return "exclamationmark.arrow.triangle.2.circlepath"
        case .unknown:            return "bell.fill"
        }
    }

    static func iconColor(for type: ActivityNotification.NotificationType) -> Color {
        switch type {
        case .newVideo:           return .brandNavy
        case .coachComment:       return .green
        case .invitationReceived: return .indigo
        case .invitationAccepted: return .green
        case .invitationDeclined: return .secondary
        case .accessRevoked:      return Theme.warning
        case .accessLapsed:       return .yellow
        case .accessRestorePending: return Theme.warning
        case .uploadFailed:       return .red
        case .unknown:            return .secondary
        }
    }
}
