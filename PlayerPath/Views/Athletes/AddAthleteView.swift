//
//  AddAthleteView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData
import FirebaseAuth
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "AddAthleteView")

struct AddAthleteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    let user: User
    @Binding var selectedAthlete: Athlete?
    let isFirstAthlete: Bool
    @State private var athleteName = ""
    @State private var trackStats = true
    @State private var showingSuccessAlert = false
    @State private var isCreatingAthlete = false
    @State private var showingValidationError = false
    @State private var validationErrorMessage = ""
    @State private var successMessage = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 40) {
                    if authManager.userRole == .athlete {
                        if isFirstAthlete {
                            OnboardingStepIndicator(currentStep: 0, totalSteps: 3)
                                .padding(.top, 8)
                        }

                        Spacer()
                            .frame(height: 20)

                        VStack(spacing: 24) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 100))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.brandNavy, .green],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.brandNavy.opacity(0.3), radius: 10, x: 0, y: 5)

                            VStack(spacing: 16) {
                                Text(isFirstAthlete ? "Ready to Track!" : "New Athlete")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)

                                Text(isFirstAthlete ? "Enter your athlete's name to get started." : "Add another athlete to track.")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }

                        if !isFirstAthlete {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("What You Can Track:")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .padding(.bottom, 8)

                                FeatureHighlight(
                                    icon: "video.circle.fill",
                                    title: "Record & Analyze",
                                    description: "Capture sessions and games"
                                )

                                FeatureHighlight(
                                    icon: "chart.line.uptrend.xyaxis.circle.fill",
                                    title: "Track Statistics",
                                    description: "Monitor batting averages and performance metrics"
                                )

                                FeatureHighlight(
                                    icon: "arrow.triangle.2.circlepath.circle.fill",
                                    title: "Sync Everywhere",
                                    description: "Your data syncs securely across all devices"
                                )
                            }
                            .padding(.horizontal)
                        }

                        VStack(spacing: 12) {
                            TextField("Athlete Name", text: $athleteName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($isNameFieldFocused)
                                .textContentType(.name)
                                .submitLabel(.done)
                                .id("athleteNameField")
                                .onSubmit {
                                    if isValidAthleteName(athleteName) && !isCreatingAthlete {
                                        saveAthlete()
                                    }
                                }
                                .accessibilityLabel("Athlete name")
                                .accessibilityHint("Enter the athlete's name")

                            if !isFirstAthlete {
                                VStack(alignment: .leading, spacing: 6) {
                                    Toggle("Track statistics for this athlete", isOn: $trackStats)
                                        .tint(.brandNavy)
                                    Text("Turn off to record and review videos without play-result tagging. You can change this later in athlete settings.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 4)
                            }

                            Button(action: { Haptics.light(); saveAthlete() }) {
                                HStack(spacing: 10) {
                                    if isCreatingAthlete {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    }
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                    Text(isFirstAthlete ? "Create First Athlete" : "Create Athlete")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .background(
                                    LinearGradient(
                                        colors: [Color.brandNavy, Color.brandNavy.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .shadow(color: Color.brandNavy.opacity(0.4), radius: 12, x: 0, y: 6)
                            }
                            .buttonStyle(.plain)
                            .disabled(!isValidAthleteName(athleteName) || isCreatingAthlete)
                            .accessibilityLabel(isFirstAthlete ? "Create first athlete profile" : "Create athlete profile")
                            .accessibilityHint("Creates a new athlete profile to start tracking performance")
                            .accessibilityIdentifier("create_first_athlete")
                            .accessibilitySortPriority(1)
                        }
                        .padding(.top, 20)

                        Text("You can add more athletes later in your profile settings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 40)
                    } else {
                        EmptyStateView(
                            systemImage: "person.fill.questionmark",
                            title: "Coach Accounts",
                            message: "Coaches don't create athletes. Ask your athletes to share a folder with you.",
                            actionTitle: nil,
                            action: nil
                        )
                        .padding()
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: isNameFieldFocused) { _, focused in
                if focused {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("athleteNameField", anchor: .center)
                    }
                }
            }
            } // ScrollViewReader
            .navigationTitle(isFirstAthlete ? "Get Started" : "New Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isFirstAthlete {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: saveAthlete) {
                            HStack {
                                if isCreatingAthlete {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle())
                                }
                                Text(isCreatingAthlete ? "Saving..." : "Save")
                            }
                        }
                        .disabled(!isValidAthleteName(athleteName) || isCreatingAthlete)
                        .accessibilityLabel("Save athlete")
                        .accessibilityHint("Creates the new athlete profile")
                    }
                }
            }
            .onAppear {
                isNameFieldFocused = true
            }
        }
        .toast(isPresenting: $showingSuccessAlert, message: "Athlete Added")
        .onChange(of: showingSuccessAlert) { _, new in
            if !new { dismiss() }
        }
        .alert("Unable to Save Athlete", isPresented: $showingValidationError) {
            Button("OK") { }
        } message: {
            Text(validationErrorMessage)
        }
    }

    // MARK: - Validation Functions

    private func isValidAthleteName(_ name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Validation.isValidPersonName(trimmedName, min: 2, max: 50) && !isDuplicateAthleteName(trimmedName)
    }

    private func getNameValidationMessage(_ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            return "Name cannot be empty"
        } else if trimmedName.count < 2 {
            return "Name must be at least 2 characters"
        } else if trimmedName.count > 50 {
            return "Name must be 50 characters or less"
        } else if !Validation.isValidPersonName(trimmedName, min: 2, max: 50) {
            return "Name can only contain letters, spaces, periods, hyphens, and apostrophes"
        } else if isDuplicateAthleteName(trimmedName) {
            return "An athlete with this name already exists"
        } else {
            return "Valid name"
        }
    }

    private func isDuplicateAthleteName(_ name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (user.athletes ?? []).contains { athlete in
            athlete.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmedName
        }
    }

    private func saveAthlete() {
        // Final validation before saving
        let trimmedName = athleteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAthleteName(trimmedName) else {
            validationErrorMessage = getNameValidationMessage(trimmedName)
            showingValidationError = true
            return
        }

        // Enforce tier limit using live StoreKit tier (not stale SwiftData user.tier)
        let liveTier = authManager.currentTier
        let currentCount = (user.athletes ?? []).count
        guard currentCount < liveTier.athleteLimit else {
            let upgradeMessage: String
            switch liveTier {
            case .free: upgradeMessage = "Upgrade to Plus to track up to 3 athletes, or Pro to track up to 5."
            case .plus: upgradeMessage = "Upgrade to Pro to track up to 5 athletes."
            case .pro:  upgradeMessage = "You've reached the maximum of 5 athletes."
            }
            validationErrorMessage = "You've reached the \(liveTier.athleteLimit)-athlete limit for your \(liveTier.displayName) plan. \(upgradeMessage)"
            showingValidationError = true
            return
        }

        isCreatingAthlete = true

        Task {
            let athlete = Athlete(name: trimmedName)

            // Set up relationship BEFORE inserting
            athlete.user = user

            // Apply stat tracking preference (only asked for second+ athletes;
            // first athlete always defaults to tracking on).
            if !isFirstAthlete {
                athlete.trackStatsEnabled = trackStats
            }

            // Mark for Firestore sync
            athlete.needsSync = true

            // Insert in model context
            modelContext.insert(athlete)

            log.debug("Attempting to save athlete '\(trimmedName, privacy: .private)' for user: \(user.id, privacy: .private)")
            log.debug("User email: \(user.email, privacy: .private)")
            log.debug("User currently has \((user.athletes ?? []).count) athletes")
            log.debug("Firebase user: \(authManager.currentFirebaseUser?.email ?? "None", privacy: .private)")

            do {
                try modelContext.save()
                log.info("Successfully saved athlete '\(trimmedName, privacy: .private)' with ID: \(athlete.id, privacy: .private)")

                // Track athlete creation analytics
                AnalyticsService.shared.trackAthleteCreated(
                    athleteID: athlete.id.uuidString,
                    isFirstAthlete: isFirstAthlete
                )

                // SwiftData should have already updated the relationship via inverse
                // But we verify and log for debugging
                await MainActor.run {
                    log.debug("User now has \((user.athletes ?? []).count) athletes")

                    // Auto-select the new athlete
                    selectedAthlete = athlete

                    // Track athlete selection analytics
                    AnalyticsService.shared.trackAthleteSelected(athleteID: athlete.id.uuidString)

                    log.debug("Selected new athlete: \(athlete.name, privacy: .private) (ID: \(athlete.id, privacy: .private))")

                    // Trigger immediate sync to Firestore
                    Task {
                        do {
                            try await SyncCoordinator.shared.syncAthletes(for: user)
                        } catch {
                            // Don't block athlete creation on sync failure
                        }
                    }
                }

                // If this was the first athlete, mark onboarding complete but DON'T reset new user flag yet
                // The new user flag will be reset when the first season is created
                if isFirstAthlete {
                    await MainActor.run {
                        // Create onboarding progress record to persist completion
                        let progress = OnboardingProgress(firebaseAuthUid: authManager.currentFirebaseUser?.uid ?? "")
                        progress.markCompleted()
                        modelContext.insert(progress)

                        // Save to SwiftData
                        do {
                            try modelContext.save()
                            log.debug("Saved onboarding completion to SwiftData")
                        } catch {
                            ErrorHandlerService.shared.handle(error, context: "AddAthleteView.saveOnboardingProgress", showAlert: false)
                        }

                        // Mark onboarding complete in auth manager (for session state)
                        authManager.markOnboardingComplete()

                        // DON'T reset new user flag here - let season creation do it
                        log.debug("First athlete created - user still flagged as new until season created")
                    }
                }

                // Haptics
                Haptics.medium()

                // For first athlete, don't show success alert - transition directly to season creation
                // For additional athletes, show success alert
                if isFirstAthlete {
                    await MainActor.run {
                        isCreatingAthlete = false
                        athleteName = ""
                        // Don't show alert or dismiss - UserMainFlow will navigate to season creation
                    }
                } else {
                    let message = "Athlete '\(trimmedName)' has been added successfully! You can now start tracking their performance."
                    await MainActor.run {
                        successMessage = message
                        isCreatingAthlete = false
                        athleteName = ""
                        showingSuccessAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isCreatingAthlete = false
                    validationErrorMessage = getErrorMessage(for: error)
                    showingValidationError = true
                }
            }
        }
    }

    private func getErrorMessage(for error: Error) -> String {
        let errorDescription = error.localizedDescription.lowercased()

        if errorDescription.contains("unique") || errorDescription.contains("duplicate") {
            return "An athlete with this name already exists. Please choose a different name."
        } else if errorDescription.contains("network") || errorDescription.contains("connection") {
            return "Unable to save due to connection issues. Please check your internet and try again."
        } else {
            return "Unable to save athlete. Please try again in a moment."
        }
    }
}
