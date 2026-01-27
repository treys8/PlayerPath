//
//  AddAthleteView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct AddAthleteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    let user: User
    @Binding var selectedAthlete: Athlete?
    let isFirstAthlete: Bool
    @State private var athleteName = ""
    @State private var showingSuccessAlert = false
    @State private var isCreatingAthlete = false
    @State private var showingValidationError = false
    @State private var validationErrorMessage = ""
    @State private var successMessage = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 40) {
                    if authManager.userRole == .athlete {
                        Spacer()
                            .frame(height: 20)

                        VStack(spacing: 24) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 100))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .green],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)

                            VStack(spacing: 16) {
                                Text("Ready to Track!")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)

                                Text("Create your first profile to get started.")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }

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

                        VStack(spacing: 12) {
                            TextField("Athlete Name", text: $athleteName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($isNameFieldFocused)
                                .textContentType(.name)
                                .submitLabel(.done)
                                .onSubmit {
                                    if isValidAthleteName(athleteName) && !isCreatingAthlete {
                                        saveAthlete()
                                    }
                                }
                                .accessibilityLabel("Athlete name")
                                .accessibilityHint("Enter the athlete's name")

                            Button(action: { Haptics.light(); saveAthlete() }) {
                                HStack {
                                    if isCreatingAthlete {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    }
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                    Text("Create First Athlete")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(!isValidAthleteName(athleteName) || isCreatingAthlete)
                            .accessibilityLabel("Create first athlete profile")
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
            .navigationTitle(isFirstAthlete ? "Get Started" : "New Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .onAppear {
                // Auto-focus the name field when the view appears
                isNameFieldFocused = true
            }
        }
        .alert("Success! 🎉", isPresented: $showingSuccessAlert) {
            Button("Continue") {
                dismiss()
            }
        } message: {
            Text(successMessage)
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
        isCreatingAthlete = true

        Task {
            let athlete = Athlete(name: trimmedName)

            // Set up relationship BEFORE inserting
            athlete.user = user

            // Mark for Firestore sync
            athlete.needsSync = true

            // Insert in model context
            modelContext.insert(athlete)

            #if DEBUG
            print("🟡 Attempting to save athlete '\(trimmedName)' for user: \(user.id)")
            print("🟡 User email: \(user.email)")
            print("🟡 User currently has \((user.athletes ?? []).count) athletes")
            print("🟡 Firebase user: \(authManager.currentFirebaseUser?.email ?? "None")")
            #endif

            do {
                try modelContext.save()
                #if DEBUG
                print("🟢 Successfully saved athlete '\(trimmedName)' with ID: \(athlete.id)")
                #endif

                // Track athlete creation analytics
                AnalyticsService.shared.trackAthleteCreated(
                    athleteID: athlete.id.uuidString,
                    isFirstAthlete: isFirstAthlete
                )

                // SwiftData should have already updated the relationship via inverse
                // But we verify and log for debugging
                await MainActor.run {
                    #if DEBUG
                    print("🟢 User now has \((user.athletes ?? []).count) athletes")
                    #endif

                    // Auto-select the new athlete
                    selectedAthlete = athlete

                    // Track athlete selection analytics
                    AnalyticsService.shared.trackAthleteSelected(athleteID: athlete.id.uuidString)

                    #if DEBUG
                    print("🟢 Selected new athlete: \(athlete.name) (ID: \(athlete.id))")
                    #endif

                    // Trigger immediate sync to Firestore
                    Task {
                        do {
                            try await SyncCoordinator.shared.syncAthletes(for: user)
                            print("✅ Athlete synced to Firestore successfully")
                        } catch {
                            print("⚠️ Failed to sync athlete to Firestore: \(error)")
                            // Don't block athlete creation on sync failure
                        }
                    }
                }

                // If this was the first athlete, mark onboarding complete and clear the new user flag
                if isFirstAthlete {
                    await MainActor.run {
                        // Create onboarding progress record to persist completion
                        let progress = OnboardingProgress()
                        progress.markCompleted()
                        modelContext.insert(progress)

                        // Save to SwiftData
                        do {
                            try modelContext.save()
                            #if DEBUG
                            print("🟢 Saved onboarding completion to SwiftData")
                            #endif
                        } catch {
                            print("🔴 Failed to save onboarding progress: \(error)")
                        }

                        // Mark onboarding complete in auth manager (for session state)
                        authManager.markOnboardingComplete()

                        // Reset the new user flag
                        authManager.resetNewUserFlag()
                        #if DEBUG
                        print("🟢 First athlete created - onboarding completed and new user flag reset")
                        #endif
                    }
                }

                // Haptics
                Haptics.medium()

                // Success messaging
                let message = isFirstAthlete
                    ? "Welcome to PlayerPath! Athlete '\(trimmedName)' has been created and you're ready to start tracking performance."
                    : "Athlete '\(trimmedName)' has been added successfully! You can now start tracking their performance."
                await MainActor.run {
                    successMessage = message
                    isCreatingAthlete = false
                    athleteName = ""
                    showingSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isCreatingAthlete = false
                    validationErrorMessage = getErrorMessage(for: error)
                    showingValidationError = true
                }
                print("🔴 Failed to save athlete: \(error)")
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
