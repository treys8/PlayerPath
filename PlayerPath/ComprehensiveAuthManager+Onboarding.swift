//
//  ComprehensiveAuthManager+Onboarding.swift
//  PlayerPath
//
//  Onboarding completion helper shared by Athlete and Coach onboarding flows.
//

import Foundation
import SwiftData
import FirebaseAuth

extension ComprehensiveAuthManager {
    /// Marks onboarding as complete for the current user: inserts an
    /// `OnboardingProgress` record into the provided context, saves it with retry,
    /// then updates auth flags. On save failure, throws — caller is responsible
    /// for rolling back the context.
    @MainActor
    func completeOnboarding(
        in context: ModelContext,
        resetNewUserFlag: Bool
    ) async throws {
        let progress = OnboardingProgress(firebaseAuthUid: userID ?? "")
        progress.markCompleted()
        context.insert(progress)
        try await withRetry(delay: .seconds(1)) {
            try context.save()
        }
        if resetNewUserFlag {
            self.resetNewUserFlag()
        }
        markOnboardingComplete()
    }

    // MARK: - Pending onboarding (survives relaunch)

    /// `isNewUser` is session-only (see init). This UID-scoped marker is the
    /// durable record that sign-up happened but onboarding hasn't finished, so a
    /// relaunch during email verification (Mail → tap link → iOS kills us) still
    /// routes to onboarding. Deliberately NOT cleared on sign-out: "Use a
    /// Different Account" followed by signing back in must resume it.
    func markOnboardingPending(uid: String) {
        UserDefaults.standard.set(uid, forKey: AuthConstants.UserDefaultsKeys.pendingOnboardingUID)
    }

    func clearPendingOnboarding() {
        UserDefaults.standard.removeObject(forKey: AuthConstants.UserDefaultsKeys.pendingOnboardingUID)
    }

    /// Re-arms `isNewUser` for a session whose onboarding never finished.
    /// Call AFTER the profile load (a true `isNewUser` makes profile loads keep
    /// the pre-set role instead of Firestore's) and BEFORE `isSignedIn = true`
    /// (AuthenticatedFlow reads `isNewUser` as it appears).
    func restorePendingOnboardingIfNeeded(for user: FirebaseAuth.User) {
        guard !isNewUser,
              UserDefaults.standard.string(forKey: AuthConstants.UserDefaultsKeys.pendingOnboardingUID) == user.uid
        else { return }
        // Bounded so a stale marker (e.g. onboarding finished on another
        // device) can't drop an established account back into setup forever.
        let created = user.metadata.creationDate ?? .distantPast
        guard Date().timeIntervalSince(created) < 14 * 24 * 60 * 60 else {
            clearPendingOnboarding()
            return
        }
        isNewUser = true
    }
}
