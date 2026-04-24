//
//  ComprehensiveAuthManager+Onboarding.swift
//  PlayerPath
//
//  Onboarding completion helper shared by Athlete and Coach onboarding flows.
//

import Foundation
import SwiftData

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
}
