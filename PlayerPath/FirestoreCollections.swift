//
//  FirestoreCollections.swift
//  PlayerPath
//
//  Centralized Firestore collection name constants.
//  Using these instead of inline strings prevents silent bugs from typos.
//

import Foundation

enum FC {
    // Top-level collections
    static let users = "users"
    static let videos = "videos"
    static let sharedFolders = "sharedFolders"
    static let invitations = "invitations"
    static let photos = "photos"
    static let coachSessions = "coachSessions"
    static let pendingDeletions = "pendingDeletions"
    static let coachAccessRevocations = "coach_access_revocations"
    static let appConfig = "appConfig"

    // Subcollections
    static let athletes = "athletes"
    static let seasons = "seasons"
    static let games = "games"
    static let practices = "practices"
    static let notes = "notes"
    static let coaches = "coaches"
    static let annotations = "annotations"
    static let comments = "comments"
    static let drillCards = "drillCards"
    static let coachTemplates = "coachTemplates"
    static let quickCues = "quickCues"
    static let drillCardTemplates = "drillCardTemplates"
    static let notifications = "notifications"
    static let items = "items"
}
