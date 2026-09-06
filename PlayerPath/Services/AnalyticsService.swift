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
    private static let iso8601Formatter = ISO8601DateFormatter()

    private init() {
        configureAnalytics()
    }

    // MARK: - Configuration

    private func configureAnalytics() {
        // Deliberately does NOT call setAnalyticsCollectionEnabled here.
        //
        // It used to force `true` unconditionally, which had two problems. Firebase PERSISTS
        // this flag across launches, so forcing it on every cold start silently overrode a
        // user who had opted out — and it overrode IS_ANALYTICS_ENABLED=false in
        // GoogleService-Info.plist besides. Worse, `MainAppView.task` is what applies the
        // real stored preference, and it runs *after* this singleton is first touched, so an
        // opted-out user was collected for the whole window in between, every launch.
        //
        // Leaving the flag alone means Firebase restores the last persisted value, so an
        // opt-out is honoured from process start; MainAppView then re-affirms it from
        // UserPreferences (which lives in SwiftData and cannot be read from here anyway).
        setDefaultUserProperties()
    }

    /// Updates analytics and crash-reporting collection to match the user's preference.
    /// Call this once after loading UserPreferences, and again whenever the toggle changes.
    func setCollection(enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
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

    // MARK: - Coach Connection Events

    /// Logged when an athlete accepts a coach's invitation. Also stamps the
    /// `acquisition_source` user property so paywall/subscription conversions can
    /// be segmented coach-invited vs organic (the key instructor-channel metric).
    func trackCoachInvitationAccepted(coachID: String?) {
        logEvent(.coachInvitationAccepted, parameters: [
            "coach_id": coachID ?? "unknown"
        ])
        Analytics.setUserProperty("coach_invited", forName: "acquisition_source")
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

    // MARK: - Recruiting Profile Events

    /// Fired when a recruiting profile is saved. `isFirstSave` distinguishes
    /// creation from edits; `fieldsCompleted` feeds the fill-in-rate metric that
    /// gates the Phase 2 (public web page) investment.
    func trackRecruitingProfileSaved(athleteID: String, sport: String, isFirstSave: Bool,
                                     hasHeadshot: Bool, fieldsCompleted: Int) {
        logEvent(isFirstSave ? .recruitingProfileCreated : .recruitingProfileEdited, parameters: [
            "athlete_id": athleteID,
            "sport": sport,
            "has_headshot": hasHeadshot,
            "fields_completed": fieldsCompleted
        ])
    }

    /// Fired when a profile goes live at its public link. `clipCount` is the
    /// headline health metric — a published profile with film is the outcome the
    /// feature exists for; one without is a fill-in that never converted.
    func trackRecruitingProfilePublished(athleteID: String, sport: String,
                                         clipCount: Int, isFirstPublish: Bool) {
        logEvent(.recruitingProfilePublished, parameters: [
            "athlete_id": athleteID,
            "sport": sport,
            "clip_count": clipCount,
            "is_first_publish": isFirstPublish
        ])
    }

    /// Fired when an athlete takes their public page down. Watch this against
    /// publishes — a high unpublish rate means the page isn't doing its job.
    func trackRecruitingProfileUnpublished(athleteID: String, sport: String) {
        logEvent(.recruitingProfileUnpublished, parameters: [
            "athlete_id": athleteID,
            "sport": sport
        ])
    }

    /// Fired on "Reset Link" — the old share URL is dead, a new token is live.
    /// A spike here means links are leaking somewhere athletes regret.
    func trackRecruitingLinkReset(athleteID: String, sport: String) {
        logEvent(.recruitingLinkReset, parameters: [
            "athlete_id": athleteID,
            "sport": sport
        ])
    }

    /// Fired on "Delete Profile Data" — the published doc and headshot are gone.
    /// Kept separate from unpublish on purpose: unpublish is reversible and often
    /// seasonal, while this is a family withdrawing from the feature, and folding
    /// the two together would hide that behind a metric that looks like churn
    /// noise.
    func trackRecruitingProfileDataDeleted(athleteID: String, sport: String) {
        logEvent(.recruitingProfileDataDeleted, parameters: [
            "athlete_id": athleteID,
            "sport": sport
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

    /// `count` is clips that actually landed. NOTE: once de-duplication shipped,
    /// identical user behavior produces a lower `count` than it used to — read it
    /// alongside `skipped_duplicates` rather than comparing the series across
    /// that boundary.
    func trackVideosBulkImported(
        count: Int,
        skippedDuplicates: Int,
        stoppedForQuota: Bool,
        wasResume: Bool,
        totalSizeBytes: Int64
    ) {
        logEvent(.videosBulkImported, parameters: [
            "count": count,
            "skipped_duplicates": skippedDuplicates,
            "stopped_for_quota": stoppedForQuota,
            // A batch stopped by the storage cap and resumed after an upgrade
            // fires this event twice for ONE user action. Filter or collapse on
            // this flag rather than counting rows.
            "was_resume": wasResume,
            "total_size_mb": Int(totalSizeBytes / 1_048_576)
        ])
    }

    /// Photo mirror of `trackVideosBulkImported`. Counts and sizes only — never
    /// captions, file names, or season names (user-typed free text that in youth
    /// sports identifies a minor).
    func trackPhotosBulkImported(
        count: Int,
        skippedDuplicates: Int,
        stoppedForQuota: Bool,
        wasResume: Bool,
        totalSizeBytes: Int64
    ) {
        logEvent(.photosBulkImported, parameters: [
            "count": count,
            "skipped_duplicates": skippedDuplicates,
            "stopped_for_quota": stoppedForQuota,
            // See trackVideosBulkImported: a resumed batch is a second event for
            // one user action.
            "was_resume": wasResume,
            "total_size_mb": Int(totalSizeBytes / 1_048_576)
        ])
    }

    // MARK: - Game Events

    func trackGameCreated(gameID: String, opponent: String, isLive: Bool) {
        logEvent(.gameCreated, parameters: [
            "game_id": gameID,
            // Presence, not the value. `opponent` is free text the user typed and in youth
            // sports it is usually a school or club name — a locatable detail about a minor,
            // joined to the Auth UID by setUserID and uploaded to Google Analytics, which
            // prohibits PII in event parameters. The product question this event answers is
            // "did they bother filling it in", which the boolean answers just as well.
            "has_opponent": !opponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
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

    // MARK: - Premium Features

    func trackPaywallShown(source: String) {
        logEvent(.paywallShown, parameters: [
            "source": source
        ])
    }

    /// Fires when the paywall closes WITHOUT a successful purchase. The
    /// shown→dismissed delta is the top of the conversion funnel.
    func trackPaywallDismissed(source: String, selectedTier: String, isAnnual: Bool) {
        logEvent(.paywallDismissed, parameters: [
            "source": source,
            "selected_tier": selectedTier,
            "period": isAnnual ? "annual" : "monthly"
        ])
    }

    /// Fires the moment the user taps the purchase CTA, before StoreKit shows
    /// its system sheet. Used as the denominator for purchase-completion rate.
    func trackPaywallPurchaseAttempted(source: String, productID: String, tier: String, isAnnual: Bool) {
        logEvent(.paywallPurchaseAttempted, parameters: [
            "source": source,
            "product_id": productID,
            "tier": tier,
            "period": isAnnual ? "annual" : "monthly"
        ])
    }

    func trackPaywallPurchaseSucceeded(source: String, productID: String, tier: String, isAnnual: Bool, price: String) {
        logEvent(.paywallPurchaseSucceeded, parameters: [
            "source": source,
            "product_id": productID,
            "tier": tier,
            "period": isAnnual ? "annual" : "monthly",
            "price": price
        ])
    }

    /// `reason` distinguishes user-cancel from system error so funnel reports
    /// can exclude cancellations from genuine failure rate.
    func trackPaywallPurchaseFailed(source: String, productID: String, tier: String, isAnnual: Bool, reason: String, errorCode: String? = nil) {
        var params: [String: Any] = [
            "source": source,
            "product_id": productID,
            "tier": tier,
            "period": isAnnual ? "annual" : "monthly",
            "reason": reason
        ]
        if let errorCode { params["error_code"] = errorCode }
        logEvent(.paywallPurchaseFailed, parameters: params)
    }

    func trackSubscriptionStarted(planType: String, price: String) {
        logEvent(.subscriptionStarted, parameters: [
            "plan_type": planType,
            "price": price
        ])
    }

    // MARK: - Win-Back Events

    func trackWinBackShown(productID: String, tierName: String, reason: String) {
        logEvent(.winBackShown, parameters: [
            "product_id": productID,
            "tier": tierName,
            "lapse_reason": reason
        ])
    }

    /// The verbatim `feedbackText` parameter is gone on purpose — do not reinstate it.
    ///
    /// It uploaded whatever the user typed into a cancellation box, unscrubbed, to Google
    /// Analytics, joined to their Auth UID by `setUserID`. That box is exactly where someone
    /// writes "my daughter Emma is done for the season, email me at jane@gmail.com" — names,
    /// addresses and phone numbers of a minor, with no user-facing deletion path and in
    /// breach of the Analytics ToS ban on PII in event parameters. The 100-char truncation
    /// was a Firebase field limit, never a privacy control.
    ///
    /// `has_free_text` is retained and is the actual product metric: it answers "do people
    /// bother elaborating", which is what the funnel needs. If the verbatim text is ever
    /// genuinely wanted, it belongs in your own backend behind a consent string — not here.
    func trackWinBackReasonSubmitted(productID: String, tierName: String, reason: String, cancellationReason: String, hasFreeText: Bool) {
        logEvent(.winBackReasonSubmitted, parameters: [
            "product_id": productID,
            "tier": tierName,
            "lapse_reason": reason,
            "cancellation_reason": cancellationReason,
            "has_free_text": hasFreeText
        ])
    }

    func trackWinBackDismissed(productID: String, tierName: String, reason: String) {
        logEvent(.winBackDismissed, parameters: [
            "product_id": productID,
            "tier": tierName,
            "lapse_reason": reason
        ])
    }

    // MARK: - Onboarding Events

    func trackOnboardingStarted(role: String) {
        logEvent(.onboardingStarted, parameters: [
            "role": role
        ])
    }

    func trackOnboardingStepView(role: String, step: Int, stepName: String) {
        logEvent(.onboardingStepView, parameters: [
            "role": role,
            "step": step,
            "step_name": stepName
        ])
    }

    func trackOnboardingCompleted(role: String) {
        logEvent(.onboardingCompleted, parameters: [
            "role": role
        ])
    }

    /// `lastStep` is the highest-numbered step the user saw before bailing.
    /// 0 means they didn't get past the welcome screen.
    func trackOnboardingAbandoned(role: String, lastStep: Int) {
        logEvent(.onboardingAbandoned, parameters: [
            "role": role,
            "last_step": lastStep
        ])
    }

    // MARK: - Help & Support Events

    func trackSupportContactSubmitted(category: String) {
        logEvent(.supportContactSubmitted, parameters: [
            "category": category
        ])
    }

    // MARK: - GDPR Events

    // These four carried `"user_id": <Firebase Auth UID>` as an event PARAMETER. That is a
    // persistent identifier, which the Google Analytics ToS forbids in parameters, and it was
    // redundant besides — `setUserID` already links the whole session. The aggravating detail
    // is which events they are: the identifier was attached precisely when a family exercised
    // a privacy right, so asking for your data or deleting your account minted an extra
    // identity-linked record in Google's systems. The events themselves are worth keeping;
    // the parameter never was. Signatures keep their `userID` argument only where a caller
    // still needs it — see below, they don't, so it's gone.

    func trackDataExportRequested() {
        logEvent(.dataExportRequested)
    }

    func trackDataExportCompleted(fileSize: Int) {
        logEvent(.dataExportCompleted, parameters: [
            "file_size_kb": fileSize / 1024
        ])
    }

    func trackAccountDeletionRequested() {
        logEvent(.accountDeletionRequested)
    }

    func trackAccountDeletionCompleted() {
        logEvent(.accountDeletionCompleted)
    }

    // MARK: - Error Tracking

    func trackError(_ error: Error, context: String) {
        let errorEvent = AnalyticsEvent.error
        logEvent(errorEvent, parameters: [
            "error_domain": (error as NSError).domain,
            "error_code": (error as NSError).code,
            "context": context
            // `error_description` (localizedDescription) is deliberately NOT sent. Firebase
            // and URLSession errors routinely embed full Storage object paths — which contain
            // the owner's uid and the file name — and Firestore errors can quote document
            // contents. domain + code + context identify the failure just as well for triage.
            // The full error still reaches Crashlytics below, which is the right destination
            // for it: crash reporting, not the analytics event stream.
        ])

        Crashlytics.crashlytics().record(error: error)
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
        params["timestamp"] = Self.iso8601Formatter.string(from: Date())

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
    case videosBulkImported = "videos_bulk_imported"
    case photosBulkImported = "photos_bulk_imported"

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

    // Coach connections
    case coachInvitationAccepted = "coach_invitation_accepted"

    // Premium
    case paywallShown = "paywall_shown"
    case paywallDismissed = "paywall_dismissed"
    case paywallPurchaseAttempted = "paywall_purchase_attempted"
    case paywallPurchaseSucceeded = "paywall_purchase_succeeded"
    case paywallPurchaseFailed = "paywall_purchase_failed"
    case subscriptionStarted = "subscription_started"
    case subscriptionCancelled = "subscription_cancelled"

    // Onboarding
    case onboardingStarted = "onboarding_started"
    case onboardingStepView = "onboarding_step_view"
    case onboardingCompleted = "onboarding_completed"
    case onboardingAbandoned = "onboarding_abandoned"

    // Win-back
    case winBackShown = "win_back_shown"
    case winBackReasonSubmitted = "win_back_reason_submitted"
    case winBackDismissed = "win_back_dismissed"

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

    // Recruiting profile
    case recruitingProfileCreated = "recruiting_profile_created"
    case recruitingProfileEdited = "recruiting_profile_edited"
    case recruitingProfilePublished = "recruiting_profile_published"
    case recruitingProfileUnpublished = "recruiting_profile_unpublished"
    case recruitingLinkReset = "recruiting_link_reset"
    case recruitingProfileDataDeleted = "recruiting_profile_data_deleted"
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
