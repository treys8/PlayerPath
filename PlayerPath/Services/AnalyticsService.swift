//
//  AnalyticsService.swift
//  PlayerPath
//
//  Centralized analytics and event tracking service
//  Tracks key user actions for product insights
//

import Foundation
import FirebaseAnalytics
import FirebaseCrashlytics

/// Centralized service for tracking analytics events and crashes
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private init() {
        configureAnalytics()
    }

    // MARK: - Configuration

    private func configureAnalytics() {
        // Enable analytics collection
        Analytics.setAnalyticsCollectionEnabled(true)

        // Set user properties for segmentation
        setDefaultUserProperties()

        print("📊 Analytics configured and enabled")
    }

    private func setDefaultUserProperties() {
        // These help segment users in Firebase Console
        Analytics.setUserProperty(Bundle.main.appVersion, forName: "app_version")
        Analytics.setUserProperty(Bundle.main.buildNumber, forName: "build_number")
        Analytics.setUserProperty(UIDevice.current.systemVersion, forName: "ios_version")
        Analytics.setUserProperty(UIDevice.current.model, forName: "device_model")
    }

    // MARK: - User Identity

    func setUserID(_ userID: String) {
        Analytics.setUserID(userID)
        Crashlytics.crashlytics().setUserID(userID)
    }

    func clearUserID() {
        Analytics.setUserID(nil)
        Crashlytics.crashlytics().setUserID("")
    }

    func setUserProperty(_ value: String?, forKey key: String) {
        Analytics.setUserProperty(value, forName: key)
    }

    // MARK: - Authentication Events

    func trackSignUp(method: String) {
        logEvent(.signUp, parameters: [
            "method": method
        ])
    }

    func trackSignIn(method: String) {
        logEvent(.login, parameters: [
            "method": method
        ])
    }

    func trackSignOut() {
        logEvent(.signOut)
    }

    // MARK: - Athlete Events

    func trackAthleteCreated(athleteID: String, isFirstAthlete: Bool) {
        logEvent(.athleteCreated, parameters: [
            "athlete_id": athleteID,
            "is_first": isFirstAthlete
        ])
    }

    func trackAthleteDeleted(athleteID: String) {
        logEvent(.athleteDeleted, parameters: [
            "athlete_id": athleteID
        ])
    }

    func trackAthleteSelected(athleteID: String) {
        logEvent(.athleteSelected, parameters: [
            "athlete_id": athleteID
        ])
    }

    // MARK: - Video Events

    func trackVideoRecorded(duration: TimeInterval, quality: String, isQuickRecord: Bool) {
        logEvent(.videoRecorded, parameters: [
            "duration_seconds": Int(duration),
            "quality": quality,
            "is_quick_record": isQuickRecord
        ])
    }

    func trackVideoTagged(playResult: String, videoID: String) {
        logEvent(.videoTagged, parameters: [
            "play_result": playResult,
            "video_id": videoID
        ])
    }

    func trackVideoUploaded(fileSize: Int64, uploadDuration: TimeInterval) {
        logEvent(.videoUploaded, parameters: [
            "file_size_mb": Int(fileSize / 1_000_000),
            "upload_duration_seconds": Int(uploadDuration)
        ])
    }

    func trackVideoDeleted(videoID: String) {
        logEvent(.videoDeleted, parameters: [
            "video_id": videoID
        ])
    }

    // MARK: - Game Events

    func trackGameCreated(gameID: String, opponent: String, isLive: Bool) {
        logEvent(.gameCreated, parameters: [
            "game_id": gameID,
            "opponent": opponent,
            "is_live": isLive
        ])
    }

    func trackGameStarted(gameID: String) {
        logEvent(.gameStarted, parameters: [
            "game_id": gameID
        ])
    }

    func trackGameEnded(gameID: String, atBats: Int, hits: Int) {
        logEvent(.gameEnded, parameters: [
            "game_id": gameID,
            "at_bats": atBats,
            "hits": hits,
            "batting_average": atBats > 0 ? Double(hits) / Double(atBats) : 0.0
        ])
    }

    // MARK: - Season Events

    func trackSeasonCreated(seasonID: String, sport: String, isActive: Bool) {
        logEvent(.seasonCreated, parameters: [
            "season_id": seasonID,
            "sport": sport,
            "is_active": isActive
        ])
    }

    func trackSeasonActivated(seasonID: String) {
        logEvent(.seasonActivated, parameters: [
            "season_id": seasonID
        ])
    }

    func trackSeasonEnded(seasonID: String, totalGames: Int) {
        logEvent(.seasonEnded, parameters: [
            "season_id": seasonID,
            "total_games": totalGames
        ])
    }

    // MARK: - Statistics Events

    func trackStatsViewed(athleteID: String, viewType: String) {
        logEvent(.statsViewed, parameters: [
            "athlete_id": athleteID,
            "view_type": viewType // "overall", "season", "game"
        ])
    }

    func trackStatsExported(athleteID: String, format: String) {
        logEvent(.statsExported, parameters: [
            "athlete_id": athleteID,
            "format": format // "csv", "pdf"
        ])
    }

    // MARK: - Practice Events

    func trackPracticeCreated(practiceID: String, seasonID: String?) {
        logEvent(.practiceCreated, parameters: [
            "practice_id": practiceID,
            "season_id": seasonID ?? "none"
        ])
    }

    func trackPracticeNoteAdded(practiceID: String) {
        logEvent(.practiceNoteAdded, parameters: [
            "practice_id": practiceID
        ])
    }

    // MARK: - Sync Events

    func trackSyncStarted(entityType: String) {
        logEvent(.syncStarted, parameters: [
            "entity_type": entityType
        ])
    }

    func trackSyncCompleted(entityType: String, itemCount: Int, duration: TimeInterval) {
        logEvent(.syncCompleted, parameters: [
            "entity_type": entityType,
            "item_count": itemCount,
            "duration_seconds": Int(duration)
        ])
    }

    func trackSyncFailed(entityType: String, errorMessage: String) {
        logEvent(.syncFailed, parameters: [
            "entity_type": entityType,
            "error_message": errorMessage
        ])
    }

    // MARK: - Premium Features

    func trackPaywallShown(source: String) {
        logEvent(.paywallShown, parameters: [
            "source": source
        ])
    }

    func trackSubscriptionStarted(planType: String, price: String) {
        logEvent(.subscriptionStarted, parameters: [
            "plan_type": planType,
            "price": price
        ])
    }

    func trackSubscriptionCancelled(planType: String) {
        logEvent(.subscriptionCancelled, parameters: [
            "plan_type": planType
        ])
    }

    // MARK: - Help & Support Events

    func trackHelpArticleViewed(articleTitle: String) {
        logEvent(.helpArticleViewed, parameters: [
            "article_title": articleTitle
        ])
    }

    func trackFAQItemViewed(question: String) {
        logEvent(.faqItemViewed, parameters: [
            "question": question
        ])
    }

    func trackSupportContactSubmitted(category: String) {
        logEvent(.supportContactSubmitted, parameters: [
            "category": category
        ])
    }

    // MARK: - GDPR Events

    func trackDataExportRequested(userID: String) {
        logEvent(.dataExportRequested, parameters: [
            "user_id": userID
        ])
    }

    func trackDataExportCompleted(fileSize: Int) {
        logEvent(.dataExportCompleted, parameters: [
            "file_size_kb": fileSize / 1024
        ])
    }

    func trackAccountDeletionRequested(userID: String) {
        logEvent(.accountDeletionRequested, parameters: [
            "user_id": userID
        ])
    }

    func trackAccountDeletionCompleted(userID: String) {
        logEvent(.accountDeletionCompleted, parameters: [
            "user_id": userID
        ])
    }

    // MARK: - Error Tracking

    func trackError(_ error: Error, context: String) {
        let errorEvent = AnalyticsEvent.error
        logEvent(errorEvent, parameters: [
            "error_domain": (error as NSError).domain,
            "error_code": (error as NSError).code,
            "context": context,
            "error_description": error.localizedDescription
        ])

        Crashlytics.crashlytics().record(error: error)
    }

    func trackNetworkError(statusCode: Int, endpoint: String) {
        logEvent(.networkError, parameters: [
            "status_code": statusCode,
            "endpoint": endpoint
        ])
    }

    // MARK: - Screen Tracking

    func trackScreenView(screenName: String, screenClass: String) {
        logEvent(.screenView, parameters: [
            AnalyticsParameterScreenName: screenName,
            AnalyticsParameterScreenClass: screenClass
        ])
    }

    // MARK: - Core Logging

    private func logEvent(_ event: AnalyticsEvent, parameters: [String: Any]? = nil) {
        var params = parameters ?? [:]

        // Add timestamp to all events
        params["timestamp"] = ISO8601DateFormatter().string(from: Date())

        // Log to Firebase Analytics
        Analytics.logEvent(event.rawValue, parameters: params)

        // Debug logging
        #if DEBUG
        print("📊 Analytics Event: \(event.rawValue)")
        if let parameters = parameters {
            print("   Parameters: \(parameters)")
        }
        #endif
    }
}

// MARK: - Analytics Events Enum

enum AnalyticsEvent: String {
    // Authentication
    case signUp = "sign_up"
    case login = "login"
    case signOut = "sign_out"

    // Athletes
    case athleteCreated = "athlete_created"
    case athleteDeleted = "athlete_deleted"
    case athleteSelected = "athlete_selected"

    // Videos
    case videoRecorded = "video_recorded"
    case videoTagged = "video_tagged"
    case videoUploaded = "video_uploaded"
    case videoDeleted = "video_deleted"

    // Games
    case gameCreated = "game_created"
    case gameStarted = "game_started"
    case gameEnded = "game_ended"

    // Seasons
    case seasonCreated = "season_created"
    case seasonActivated = "season_activated"
    case seasonEnded = "season_ended"

    // Statistics
    case statsViewed = "stats_viewed"
    case statsExported = "stats_exported"

    // Practice
    case practiceCreated = "practice_created"
    case practiceNoteAdded = "practice_note_added"

    // Sync
    case syncStarted = "sync_started"
    case syncCompleted = "sync_completed"
    case syncFailed = "sync_failed"

    // Premium
    case paywallShown = "paywall_shown"
    case subscriptionStarted = "subscription_started"
    case subscriptionCancelled = "subscription_cancelled"

    // Help & Support
    case helpArticleViewed = "help_article_viewed"
    case faqItemViewed = "faq_item_viewed"
    case supportContactSubmitted = "support_contact_submitted"

    // GDPR
    case dataExportRequested = "data_export_requested"
    case dataExportCompleted = "data_export_completed"
    case accountDeletionRequested = "account_deletion_requested"
    case accountDeletionCompleted = "account_deletion_completed"

    // Errors
    case error = "error"
    case networkError = "network_error"

    // Navigation
    case screenView = "screen_view"
}

// MARK: - Bundle Extensions

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
}
