//
//  OnboardingSeasonCreationView.swift
//  PlayerPath
//
//  Created for onboarding flow - season creation step
//

import SwiftUI
import SwiftData

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
    @FocusState private var isNameFieldFocused: Bool

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
                VStack(spacing: 40) {
                    Spacer()
                        .frame(height: 20)

                    // Header with icon
                    VStack(spacing: 24) {
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
                                .font(.system(size: 80, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.green, .blue],
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
                                .multilineTextAlignment(.center)

                            Text("Organize your games and track progress over time")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }

                    // Feature highlights
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Why Seasons Matter:")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .padding(.bottom, 8)

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

                            TextField("e.g. Spring 2025", text: $seasonName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($isNameFieldFocused)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .onSubmit {
                                    if !seasonName.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating {
                                        createSeason()
                                    }
                                }

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
                                                    .background(.blue.opacity(0.1))
                                                    .foregroundStyle(.blue)
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
                            }
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Create Season")
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: .blue.opacity(0.4), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(seasonName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                    .opacity(seasonName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1.0)
                    .padding(.horizontal)

                    Text("You can create more seasons later in settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)
                }
                .padding()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Auto-select first suggestion after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if seasonName.isEmpty, let firstSuggestion = suggestedSeasons.first {
                    seasonName = firstSuggestion
                }
            }
        }
    }

    private func createSeason() {
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
        season.athlete = athlete

        // Initialize the seasons array if needed and add the season
        if athlete.seasons == nil {
            athlete.seasons = []
        }
        athlete.seasons?.append(season)

        // Mark for Firestore sync
        season.needsSync = true

        // Insert into context
        modelContext.insert(season)

        do {
            try modelContext.save()

            // Track analytics
            AnalyticsService.shared.trackSeasonCreated(
                seasonID: season.id.uuidString,
                sport: selectedSport.rawValue,
                isActive: true
            )

            #if DEBUG
            print("🟢 Onboarding season created: \(trimmedName)")
            print("🟢 Proceeding to backup preferences step...")
            #endif

            // DON'T reset new user flag here - let OnboardingBackupView do it
            // This allows the flow to continue to the backup preferences screen

            // Trigger sync to Firestore
            Task {
                guard let user = athlete.user else { return }
                do {
                    try await SyncCoordinator.shared.syncSeasons(for: user)
                    print("✅ Onboarding season synced to Firestore successfully")
                } catch {
                    print("⚠️ Failed to sync onboarding season to Firestore: \(error)")
                }
            }

            Haptics.medium()
            isCreating = false
        } catch {
            // Rollback on failure
            modelContext.delete(season)
            athlete.seasons?.removeAll { $0.id == season.id }

            isCreating = false
            errorMessage = "Failed to create season: \(error.localizedDescription)"
            showingError = true
            print("🔴 Failed to create onboarding season: \(error)")
        }
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
