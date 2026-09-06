//
//  OnboardingFunnelTracker.swift
//  PlayerPath
//
//  Single owner of the athlete signup funnel. The steps live in four different
//  views across three files and none of them can see the whole flow, so every
//  step hook reports here instead.
//
//  State is persisted per Firebase UID because `isNewUser` is session-level and
//  is NOT restored on launch (see ComprehensiveAuthManager). A user who kills
//  the app mid-flow is routed straight past the remaining steps on relaunch and
//  can never finish — a real, unrecoverable drop-out. `sweepUnfinishedFunnel`
//  is what reports it, on the next launch rather than on the first
//  backgrounding: backgrounding alone (checking a text during signup) is not
//  abandonment, and firing there would badly over-count.
//

import Foundation
import OSLog

@MainActor
final class OnboardingFunnelTracker {
    static let shared = OnboardingFunnelTracker()

    /// Funnel step numbering continues the 0/1/2 that OnboardingStepIndicator
    /// already shows on screen; 3–8 are the six welcome-tutorial pages.
    enum Step: Int {
        case athleteProfile = 0
        case seasonCreation = 1
        case backupPrefs = 2
        case tutorialManager = 3
        case tutorialPlayerReady = 4
        case tutorialGameDay = 5
        case tutorialRecord = 6
        case tutorialTagResult = 7
        case tutorialBetweenGames = 8

        var name: String {
            switch self {
            case .athleteProfile:       return "athlete_profile"
            case .seasonCreation:       return "season_creation"
            case .backupPrefs:          return "backup_prefs"
            case .tutorialManager:      return "tutorial_manager"
            case .tutorialPlayerReady:  return "tutorial_player_ready"
            case .tutorialGameDay:      return "tutorial_game_day"
            case .tutorialRecord:       return "tutorial_record"
            case .tutorialTagResult:    return "tutorial_tag_result"
            case .tutorialBetweenGames: return "tutorial_between_games"
            }
        }

        /// Maps a welcome-tutorial page index (0–5) onto its funnel step.
        static func tutorialPage(_ page: Int) -> Step? {
            Step(rawValue: page + Step.tutorialManager.rawValue)
        }

        /// Only the three setup steps may open a funnel. The tutorial is gated
        /// on `hasSeenWelcomeTutorial`, not `isNewUserFlag`, so a returning
        /// athlete can reach it (a cancelled `loadUser` skips
        /// `markWelcomeTutorialSeen`) — letting it start a funnel would log a
        /// phantom signup under role "athlete".
        var canOpenFunnel: Bool { rawValue <= Step.backupPrefs.rawValue }
    }

    /// Coaches have their own funnel in CoachOnboardingFlow; this tracker is
    /// athlete-only, so the role is fixed.
    private static let role = "athlete"

    /// Process-scoped marker, stamped onto the funnel when it opens. A funnel
    /// carrying a *different* launch's marker is the only thing the sweep may
    /// report as abandoned — an in-memory flag can't tell "opened by a previous
    /// launch" from "open right now" once the singleton is reconfigured.
    private static let launchID = UUID().uuidString

    /// Current user ID prefix for scoping keys. Empty means unscoped.
    private var userPrefix: String = ""

    /// Suppresses duplicate step views: `.onAppear` is not once-per-branch, and
    /// a branch that is removed and re-inserted re-fires it. `furthestStep`
    /// stays monotonic either way, but the per-step denominator would inflate.
    private var lastRecordedStep: Step?

    /// The funnel only operates against a real account. Unlike OnboardingManager
    /// — whose unscoped keys are idempotent booleans — `isOutcomeReported` is a
    /// one-shot latch, so a single unscoped close would silently untrack every
    /// later account on the device.
    private var isScoped: Bool { !userPrefix.isEmpty }

    private func key(_ base: String) -> String {
        "\(userPrefix)_\(base)"
    }

    private enum BaseKeys {
        static let started = "onboardingFunnelStarted"
        static let furthestStep = "onboardingFunnelFurthestStep"
        static let outcomeReported = "onboardingFunnelOutcomeReported"
        static let session = "onboardingFunnelSession"
    }

    private init() {}

    // MARK: - Lifecycle

    /// Scopes the funnel to the signed-in user and reports any funnel a previous
    /// launch left open. Call once per session, next to OnboardingManager.configure.
    func configure(forUserID userID: String?) {
        lastRecordedStep = nil

        guard let userID, !userID.isEmpty else {
            // No account to attribute to: record nothing rather than falling
            // back to device-global keys.
            userPrefix = ""
            return
        }

        userPrefix = userID
        sweepUnfinishedFunnel()
    }

    private func sweepUnfinishedFunnel() {
        guard isScoped, hasStarted, !isOutcomeReported else { return }
        // A funnel opened by *this* launch is still in progress — leave it be.
        guard sessionID != Self.launchID else { return }

        let lastStep = furthestStep
        isOutcomeReported = true
        AnalyticsService.shared.trackOnboardingAbandoned(role: Self.role, lastStep: lastStep)
        onboardingLog.info("Funnel left open by a previous launch — abandoned at step \(lastStep)")
    }

    // MARK: - Events

    /// Records the furthest step reached, firing `started` on the first setup
    /// step seen. Any of the three setup steps can be the first: a new user
    /// whose athlete arrives via sync lands on season creation without ever
    /// seeing the profile step.
    ///
    /// Tutorial steps are recorded after the funnel has already been closed by
    /// `recordCompletion` — they measure how far into the walkthrough the
    /// activated cohort gets, and never affect the funnel's outcome.
    func recordStep(_ step: Step) {
        guard isScoped else { return }

        if !hasStarted {
            guard step.canOpenFunnel, !isOutcomeReported else { return }
            hasStarted = true
            sessionID = Self.launchID
            AnalyticsService.shared.trackOnboardingStarted(role: Self.role)
        }

        guard step != lastRecordedStep else { return }
        lastRecordedStep = step

        AnalyticsService.shared.trackOnboardingStepView(
            role: Self.role,
            step: step.rawValue,
            stepName: step.name
        )

        if step.rawValue > furthestStep {
            furthestStep = step.rawValue
        }
    }

    /// Closes the funnel at the activation moment — the end of the backup step,
    /// which is the last point every athlete is guaranteed to reach. The welcome
    /// tutorial is deliberately NOT the terminator: it is presented behind
    /// `hasRunInitialSetup` and three awaits in MainTabView, so a cancelled task
    /// means it never appears, and a funnel closed there would be swept as
    /// abandoned on the next launch for a user who actually finished.
    func recordCompletion() {
        guard isScoped, hasStarted, !isOutcomeReported else { return }
        isOutcomeReported = true
        AnalyticsService.shared.trackOnboardingCompleted(role: Self.role)
    }

    // MARK: - Persisted State

    private var hasStarted: Bool {
        get { UserDefaults.standard.bool(forKey: key(BaseKeys.started)) }
        set { UserDefaults.standard.set(newValue, forKey: key(BaseKeys.started)) }
    }

    private var furthestStep: Int {
        get { UserDefaults.standard.integer(forKey: key(BaseKeys.furthestStep)) }
        set { UserDefaults.standard.set(newValue, forKey: key(BaseKeys.furthestStep)) }
    }

    private var sessionID: String? {
        get { UserDefaults.standard.string(forKey: key(BaseKeys.session)) }
        set { UserDefaults.standard.set(newValue, forKey: key(BaseKeys.session)) }
    }

    /// Set by either a completion or an abandonment sweep. Once reported, the
    /// funnel can never re-open for this user — that's what keeps a
    /// kill-and-relaunch from inflating the denominator.
    private var isOutcomeReported: Bool {
        get { UserDefaults.standard.bool(forKey: key(BaseKeys.outcomeReported)) }
        set { UserDefaults.standard.set(newValue, forKey: key(BaseKeys.outcomeReported)) }
    }
}
