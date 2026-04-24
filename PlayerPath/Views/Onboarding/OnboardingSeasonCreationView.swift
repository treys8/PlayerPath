//
//  OnboardingSeasonCreationView.swift
//  PlayerPath
//
//  Created for onboarding flow - season creation step
//

import SwiftUI
import SwiftData
import OSLog

struct OnboardingSeasonCreationView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    @State private var seasonName = ""
    @State private var startDate = Date()
    @State private var selectedSport: Season.SportType = .baseball
    @State private var isCreating = false
    @State private var showingError = false
    @State private var errorMessage = ""

    // Season name suggestions based on current date
    private var suggestedSeasons: [String] {
        let year = Calendar.current.component(.year, from: startDate)
        let month = Calendar.current.component(.month, from: startDate)

        if month >= 2 && month <= 6 {
            return ["Spring \(year)", "Spring Season", "\(year) Season"]
        } else if month >= 7 && month <= 10 {
            return ["Fall \(year)", "Fall Season", "\(year) Season"]
        } else {
            return ["Winter \(year)", "\(year) Season", "Off-Season"]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    OnboardingStepIndicator(currentStep: 1, totalSteps: 3)
                        .padding(.top, 8)

                    // Header with icon
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [.green.opacity(0.3), .clear],
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 80
                                    )
                                )
                                .frame(width: 160, height: 160)
                                .blur(radius: 20)

                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 60, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.green, Color.brandNavy],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .symbolRenderingMode(.hierarchical)
                                .shadow(color: .green.opacity(0.4), radius: 15, x: 0, y: 8)
                        }

                        VStack(spacing: 16) {
                            Text("Set Up Your Season")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .fontDesign(.rounded)
                                .multilineTextAlignment(.center)

                            Text("Organize your games and track progress over time")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }

                    // Feature highlights
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why Seasons Matter:")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .padding(.bottom, 2)

                        FeatureHighlight(
                            icon: "chart.bar.fill",
                            title: "Automatic Statistics",
                            description: "Track batting average and stats by season"
                        )

                        FeatureHighlight(
                            icon: "folder.fill",
                            title: "Organized Games",
                            description: "Group games and practices together"
                        )

                        FeatureHighlight(
                            icon: "arrow.up.right.circle.fill",
                            title: "Progress Tracking",
                            description: "Compare your performance across seasons"
                        )
                    }
                    .padding(.horizontal)

                    // Season creation form
                    VStack(spacing: 20) {
                        // Season name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Season Name")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            ModernTextField(
                                placeholder: "e.g. Spring 2026",
                                text: $seasonName,
                                icon: "calendar",
                                autocapitalization: .words,
                                validationState: seasonName.trimmingCharacters(in: .whitespaces).isEmpty ? .idle : .valid,
                                onSubmit: {
                                    if !seasonName.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating {
                                        createSeason()
                                    }
                                }
                            )
                            .autocorrectionDisabled()
                            .submitLabel(.done)

                            // Quick suggestions
                            if seasonName.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(suggestedSeasons, id: \.self) { suggestion in
                                            Button {
                                                seasonName = suggestion
                                                Haptics.light()
                                            } label: {
                                                Text(suggestion)
                                                    .font(.subheadline)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(Color.brandNavy.opacity(0.1))
                                                    .foregroundColor(.brandNavy)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Start date picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Start Date")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }

                        // Sport picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sport")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            Picker("Sport", selection: $selectedSport) {
                                ForEach(Season.SportType.allCases, id: \.self) { sport in
                                    Label(sport.displayName, systemImage: sport.icon)
                                        .tag(sport)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(.horizontal)

                    // Create button
                    Button(action: { Haptics.medium(); createSeason() }) {
                        HStack(spacing: 12) {
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                            Text(isCreating ? "Creating..." : "Create Season")
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
                    .disabled(seasonName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                    .opacity(seasonName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1.0)
                    .padding(.horizontal)

                    Button(action: { skipSeasonCreation() }) {
                        Text("Skip for Now")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 40)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
        }
        .alert("Unable to Create Season", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func skipSeasonCreation() {
        guard !isCreating else { return }
        isCreating = true
        Haptics.light()
        // Create a default season so the user isn't stuck without one.
        // The onboarding flow advances to OnboardingBackupView via the
        // "has seasons + isNewUser" routing in UserMainFlow.
        let year = Calendar.current.component(.year, from: Date())
        let season = Season(name: "\(year) Season", startDate: Date(), sport: selectedSport)
        season.activate()
        season.athlete = athlete
        season.needsSync = true
        modelContext.insert(season)
        let saved = ErrorHandlerService.shared.saveContext(modelContext, caller: "OnboardingSeasonCreation.skip")
        guard saved else {
            modelContext.rollback()
            isCreating = false
            errorMessage = "Could not create default season. Please try again."
            showingError = true
            return
        }
        onboardingLog.info("User skipped — created default '\(year) Season'")
        isCreating = false
    }

    private func createSeason() {
        guard !isCreating else { return }
        let trimmedName = seasonName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a season name"
            showingError = true
            return
        }

        isCreating = true

        // Create new season
        let season = Season(
            name: trimmedName,
            startDate: startDate,
            sport: selectedSport
        )
        season.activate()
        season.athlete = athlete // SwiftData auto-updates athlete.seasons via inverse relationship

        // Mark for Firestore sync
        season.needsSync = true

        // Insert into context
        modelContext.insert(season)

        let saved = ErrorHandlerService.shared.saveContext(modelContext, caller: "OnboardingSeasonCreation.create")
        guard saved else {
            // Discard the pending insert; simpler and safer than
            // stacking a delete op on an already-failed context.
            modelContext.rollback()
            isCreating = false
            errorMessage = "Could not create season. Please try again."
            showingError = true
            return
        }

        // Track analytics
        AnalyticsService.shared.trackSeasonCreated(
            seasonID: season.id.uuidString,
            sport: selectedSport.rawValue,
            isActive: true
        )

        onboardingLog.info("Season created — proceeding to backup step")

        // DON'T reset new user flag here - let OnboardingBackupView do it
        // This allows the flow to continue to the backup preferences screen

        // Trigger sync to Firestore
        Task {
            guard let user = athlete.user else { return }
            do {
                try await SyncCoordinator.shared.syncSeasons(for: user)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "OnboardingSeasonCreation.syncSeasons", showAlert: false)
            }
        }

        Haptics.medium()
        isCreating = false
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    guard let container = try? ModelContainer(for: User.self, Athlete.self, Season.self, configurations: config) else {
        return Text("Failed to create preview container")
    }

    let user = User(username: "testuser", email: "test@example.com")
    let athlete = Athlete(name: "Test Athlete")
    athlete.user = user

    container.mainContext.insert(user)
    container.mainContext.insert(athlete)

    return OnboardingSeasonCreationView(athlete: athlete)
        .modelContainer(container)
        .environmentObject(ComprehensiveAuthManager())
}
