//
//  UserMainFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData

struct UserMainFlow: View {
    let user: User
    let isNewUserFlag: Bool
    let hasCompletedOnboarding: Bool
    @Query(sort: \Athlete.createdAt) private var allAthletes: [Athlete]
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var sharedFolderManager = SharedFolderManager.shared
    @State private var selectedAthlete: Athlete?
    @State private var showCreationToast = false
    @State private var showingAthleteSelection = false
    private let userID: UUID

    // NotificationCenter observer management using StateObject
    @StateObject private var notificationManager = NotificationObserverManager()

    init(user: User, isNewUserFlag: Bool, hasCompletedOnboarding: Bool) {
        self.user = user
        self.isNewUserFlag = isNewUserFlag
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.userID = user.id
    }

    private var athletesForUser: [Athlete] {
        // Filter safely in Swift to avoid force unwrap in predicate
        allAthletes.filter { athlete in
            athlete.user?.id == userID
        }
    }

    private var resolvedAthlete: Athlete? {
        selectedAthlete ?? athletesForUser.first
    }

    var body: some View {
        Group {
            // IMPORTANT: Check if user is a coach FIRST before any athlete logic
            if authManager.userRole == .coach {
                CoachDashboardView()
                    .environmentObject(sharedFolderManager)
                    .onAppear {
                        print("🎯 UserMainFlow - Showing CoachDashboardView for user: \(user.email)")
                    }
            }
            // Show athlete selection if user explicitly requested it via "Manage Athletes"
            else if showingAthleteSelection {
                AthleteSelectionView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    authManager: authManager
                )
                .onChange(of: selectedAthlete) { _, newValue in
                    // Reset the flag when an athlete is selected
                    if newValue != nil {
                        showingAthleteSelection = false
                    }
                }
            }
            // Only check athlete-related logic if user is an athlete
            else if let athlete = resolvedAthlete {
                MainTabView(
                    user: user,
                    selectedAthlete: Binding(
                        get: { selectedAthlete ?? athlete },
                        set: { selectedAthlete = $0 }
                    )
                )
                .onAppear {
                    print("🎯 UserMainFlow - Showing MainTabView for athlete: \(athlete.name)")
                }
            } else if athletesForUser.count > 1 {
                AthleteSelectionView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    authManager: authManager
                )
            } else if athletesForUser.isEmpty && isNewUserFlag {
                // New athletes need to create their first athlete profile
                // Note: We check isNewUserFlag (not hasCompletedOnboarding) because athlete
                // onboarding completes BEFORE athlete creation, but we still need to force creation
                FirstAthleteCreationView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    authManager: authManager
                )
            } else {
                // Fallback: show athlete selection
                AthleteSelectionView(
                    user: user,
                    selectedAthlete: $selectedAthlete,
                    authManager: authManager
                )
            }
        }
        .overlay(alignment: .top) {
            if showCreationToast {
                Text("Athlete created")
                    .font(.subheadline).bold()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCreationToast)
            }
        }
        .onChange(of: athletesForUser) { _, newValue in
            #if DEBUG
            print("🟡 Athletes changed for user \(user.id) (\(user.email)): \(newValue.count) athletes")
            for athlete in newValue {
                print("  - \(athlete.name) (ID: \(athlete.id), User: \(athlete.user?.email ?? "None"))")
            }
            #endif

            // If a new athlete was created and we now have 2+ athletes, the newest one should already be selected
            // If exactly one athlete exists and none is selected, select it.
            if selectedAthlete == nil, newValue.count == 1, let only = newValue.first {
                #if DEBUG
                print("🟢 Auto-selecting only athlete: \(only.name) (ID: \(only.id))")
                #endif
                selectedAthlete = only
                showCreationToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showCreationToast = false
                }
            } else if let current = selectedAthlete {
                #if DEBUG
                print("🟡 Athletes changed. Current selection: \(current.name) (ID: \(current.id))")
                #endif
            }
        }
        .task {
            // Use task modifier for automatic cancellation handling
            print("🎯 UserMainFlow - User role: \(authManager.userRole.rawValue)")
            print("🎯 UserMainFlow - User email: \(user.email)")
            print("🎯 UserMainFlow - Athletes count: \(athletesForUser.count)")

            setupNotificationObservers()

            #if DEBUG
            print("🟡 UserMainFlow task - User: \(user.id), Athletes: \(athletesForUser.count)")
            #endif
            if selectedAthlete == nil, athletesForUser.count == 1, let only = athletesForUser.first {
                #if DEBUG
                print("🟢 Task auto-selecting athlete: \(only.name) (ID: \(only.id))")
                #endif
                selectedAthlete = only
            }
        }
    }

    // MARK: - NotificationCenter Management

    private func setupNotificationObservers() {
        // Clean up any existing observers first (safety)
        notificationManager.cleanup()

        notificationManager.observe(name: Notification.Name.showAthleteSelection) { _ in
            MainActor.assumeIsolated {
                selectedAthlete = nil
                showingAthleteSelection = true
            }
        }
    }
}
