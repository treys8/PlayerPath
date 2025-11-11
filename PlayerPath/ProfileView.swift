//
//  ProfileView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import UIKit

struct ProfileView: View {
    let user: User
    @Binding var selectedAthlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingAddAthlete = false
    @State private var showingSignOutAlert = false
    @State private var athletePendingDelete: Athlete?
    @State private var showingDeleteAthleteAlert = false
    @State private var isSigningOut = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""

    var body: some View {
        List {
            userProfileSection
            athletesSection
            settingsSection
            accountSection
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingAddAthlete) {
            AddAthleteView(user: user, selectedAthlete: $selectedAthlete, isFirstAthlete: user.athletes.isEmpty)
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isSigningOut = true
                Task {
                    await authManager.signOut()
                    isSigningOut = false
                }
            }
        } message: {
            Text("Are you sure you want to sign out? You can always sign back in later.")
        }
        .alert("Delete Athlete", isPresented: $showingDeleteAthleteAlert) {
            Button("Cancel", role: .cancel) { athletePendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let athlete = athletePendingDelete {
                    delete(athlete: athlete)
                    if user.athletes.isEmpty { selectedAthlete = nil }
                }
                athletePendingDelete = nil
            }
        } message: {
            Text("This will delete the athlete and related data. This action cannot be undone.")
        }
        .alert("Failed to Delete", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage.isEmpty ? "Please try again." : deleteErrorMessage)
        }
    }

    private var sortedAthletes: [Athlete] {
        user.athletes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - View Components

    private var userProfileSection: some View {
        Section {
            UserProfileHeader(user: user)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var athletesSection: some View {
        Section("Athletes") {
            ForEach(sortedAthletes) { athlete in
                AthleteProfileRow(
                    athlete: athlete,
                    isSelected: athlete.id == selectedAthlete?.id
                ) {
                    selectedAthlete = athlete
                }
            }
            .onDelete { offsets in
                if let index = offsets.first, index < sortedAthletes.count {
                    athletePendingDelete = sortedAthletes[index]
                    showingDeleteAthleteAlert = true
                }
            }

            Button(action: { showingAddAthlete = true }) {
                Label("Add Athlete", systemImage: "person.badge.plus")
            }
            .tint(.blue)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var settingsSection: some View {
        Section("Settings") {
            NavigationLink(destination: SettingsView(user: user)) {
                Label("Settings", systemImage: "gearshape")
            }

            NavigationLink(destination: NotificationSettingsView()) {
                Label("Notifications", systemImage: "bell")
            }

            #if DEBUG
            // TEMPORARY: CloudKit test - remove after testing
            NavigationLink(destination: CloudKitTestView()) {
                Label("CloudKit Test", systemImage: "icloud")
                    .foregroundColor(.blue)
            }
            #endif

            NavigationLink(destination: HelpSupportView()) {
                Label("Help & Support", systemImage: "questionmark.circle")
            }

            NavigationLink(destination: AboutView()) {
                Label("About PlayerPath", systemImage: "info.circle")
            }
        }
    }

    private var accountSection: some View {
        Section {
            Button("Sign Out") {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showingSignOutAlert = true
            }
            .disabled(isSigningOut)
            .opacity(isSigningOut ? 0.5 : 1.0)
            .foregroundColor(.red)
            .accessibilityLabel("Sign Out")
            .accessibilityHint("Sign out of your account")
        }
    }

    private func delete(athlete: Athlete) {
        // If deleting the selected athlete, select another or none
        if athlete.id == selectedAthlete?.id {
            selectedAthlete = user.athletes.first { $0.id != athlete.id }
        }
        modelContext.delete(athlete)
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete athlete: \(error)")
            deleteErrorMessage = error.localizedDescription
            showDeleteError = true
        }
    }

    private func signOut() {
        // Sign out from Firebase - this will trigger the auth state change
        // which will automatically update the app's state
        Task {
            await authManager.signOut()
        }

        // The PlayerPathMainView will handle navigation back to sign-in screen
        // based on the authManager.isSignedIn property change
    }
}

struct UserProfileHeader: View {
    let user: User
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 15) {
            EditableProfileImageView(user: user, size: 60) {
                // Save context when profile image is updated
                do {
                    try modelContext.save()
                    print("Profile image updated successfully")
                } catch {
                    print("Failed to save profile image update: \(error)")
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(user.username)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(user.email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let created = user.createdAt {
                    Text("Member since \(created.formatted(.dateTime.year()))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 10)
    }
}

struct AthleteProfileRow: View {
    let athlete: Athlete
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: "figure.baseball")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(athlete.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        Text("\(athlete.games.count) \(athlete.games.count == 1 ? "game" : "games")")
                        Text("•")
                        Text("\(athlete.videoClips.count) \(athlete.videoClips.count == 1 ? "clip" : "clips")")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .accessibilityLabel("Selected")
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Select this athlete")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

// MARK: - Settings Views

struct SettingsView: View {
    let user: User
    @State private var notificationsEnabled = true
    @State private var dataBackupEnabled = true

    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Text("Username")
                    Spacer()
                    Text(user.username)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Email")
                    Spacer()
                    Text(user.email)
                        .foregroundColor(.secondary)
                }

                NavigationLink(destination: EditAccountView(user: user)) {
                    Label("Edit Information", systemImage: "pencil")
                }

                Button("Change Password") {
                    // TODO: Implement password change
                }
                .foregroundColor(.blue)
            }

            Section("Preferences") {
                Toggle("Push Notifications", isOn: $notificationsEnabled)
                Toggle("Auto Backup Data", isOn: $dataBackupEnabled)
            }

            Section("Data") {
                Button("Export Data") {
                    // TODO: Implement data export
                }

                Button("Delete Account") {
                    // TODO: Implement account deletion
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EditAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var email: String
    let user: User
    @State private var showSaveError = false

    init(user: User) {
        self.user = user
        _username = State(initialValue: user.username)
        _email = State(initialValue: user.email)
    }

    var body: some View {
        Form {
            Section("Profile Picture") {
                HStack {
                    Spacer()
                    EditableProfileImageView(user: user, size: 80) {
                        // Save context when profile image is updated
                        do {
                            try modelContext.save()
                            print("Profile image updated successfully")
                        } catch {
                            print("Failed to save profile image update: \(error)")
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            }

            Section("Account Information") {
                TextField("Username", text: $username)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }

            Section {
                Button("Save Changes") {
                    save()
                }
                .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Edit Information")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Unable to Save", isPresented: $showSaveError) {
            Button("OK") { }
        } message: {
            Text("Please try again in a moment.")
        }
    }

    private func save() {
        user.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        user.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try modelContext.save(); dismiss() } catch {
            print("Failed to save user: \(error)")
            showSaveError = true
        }
    }
}

struct NotificationSettingsView: View {
    @State private var gameReminders = true
    @State private var liveGameUpdates = true

    @State private var weeklyStats = true
    @State private var monthlyReports = true

    @State private var achievements = true
    @State private var milestoneAlerts = true

    var body: some View {
        Form {
            Section("Game Notifications") {
                Toggle("Game Reminders", isOn: $gameReminders)
                Toggle("Live Game Updates", isOn: $liveGameUpdates)
            }

            Section("Statistics") {
                Toggle("Weekly Statistics", isOn: $weeklyStats)
                Toggle("Monthly Reports", isOn: $monthlyReports)
            }

            Section("Achievements") {
                Toggle("New Achievements", isOn: $achievements)
                Toggle("Milestone Alerts", isOn: $milestoneAlerts)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HelpSupportView: View {
    var body: some View {
        List {
            Section("Getting Started") {
                NavigationLink("How to record videos") {
                    Text("Tutorial content here")
                }
                NavigationLink("Understanding statistics") {
                    Text("Statistics explanation here")
                }
                NavigationLink("Managing tournaments") {
                    Text("Tournament guide here")
                }
            }

            Section("Contact") {
                Link("Email Support", destination: URL(string: "mailto:support@diamondtrack.app")!)
                Link("Visit Website", destination: URL(string: "https://diamondtrack.app")!)
            }

            Section("Legal") {
                NavigationLink("Privacy Policy") {
                    Text("Privacy policy content")
                }
                NavigationLink("Terms of Service") {
                    Text("Terms of service content")
                }
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "sportscourt.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            VStack(spacing: 10) {
                Text("PlayerPath")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version 1.0.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("The ultimate baseball journal for tracking your athletic journey. Record videos, track statistics, and relive your greatest moments.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Text("Made with ❤️ for baseball athletes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PaywallView: View {
    let user: User
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 15) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.yellow)

                    Text("Upgrade to Premium")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Unlock the full potential of your baseball journey")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Features
                VStack(spacing: 20) {
                    PaywallFeatureRow(
                        icon: "person.3.fill",
                        title: "Unlimited Athletes",
                        description: "Track multiple players"
                    )

                    PaywallFeatureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Advanced Statistics",
                        description: "Detailed analytics and trends"
                    )

                    PaywallFeatureRow(
                        icon: "icloud.and.arrow.up",
                        title: "Cloud Backup",
                        description: "Never lose your data"
                    )

                    PaywallFeatureRow(
                        icon: "square.and.arrow.up",
                        title: "Export & Share",
                        description: "Share highlight reels"
                    )
                }

                // Pricing
                VStack(spacing: 15) {
                    Text("Choose Your Plan")
                        .font(.headline)
                        .fontWeight(.bold)

                    HStack(spacing: 15) {
                        PricingCard(
                            title: "Monthly",
                            price: "$9.99",
                            period: "per month"
                        )

                        PricingCard(
                            title: "Annual",
                            price: "$59.99",
                            period: "per year",
                            savings: "Save 50%"
                        )
                    }
                }

                Button("Start Premium", action: upgradeToPremium)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)

                Text("Cancel anytime • 7-day free trial")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Later") {
                    dismiss()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func upgradeToPremium() {
        // In a real app, you'd integrate with StoreKit
        user.isPremium = true
        try? modelContext.save()
        dismiss()
    }
}

struct PaywallFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
    }
}

struct PricingCard: View {
    let title: String
    let price: String
    let period: String
    let savings: String?

    init(title: String, price: String, period: String, savings: String? = nil) {
        self.title = title
        self.price = price
        self.period = period
        self.savings = savings
    }

    var body: some View {
        VStack(spacing: 10) {
            if let savings = savings {
                Text(savings)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            }

            Text(title)
                .font(.headline)
                .fontWeight(.bold)

            Text(price)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.blue)

            Text(period)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    ProfileView(user: User(username: "test", email: "test@example.com"), selectedAthlete: .constant(nil))
        .environmentObject(ComprehensiveAuthManager())
}

// MARK: - More View

struct MoreView: View {
    let user: User
    @Binding var selectedAthlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingAddAthlete = false
    @State private var showingSettings = false
    @State private var showingSignOutAlert = false
    @State private var isSigningOut = false

    var body: some View {
        List {
            // Profile Section
            Section("Profile") {
                NavigationLink(destination: ProfileView(user: user, selectedAthlete: $selectedAthlete)) {
                        HStack {
                            EditableProfileImageView(user: user, size: 40) {
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("Failed to save profile image: \(error)")
                                }
                            }
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.username)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Subscription Section
                Section("Subscription") {
                    NavigationLink(destination: SubscriptionView(user: user)) {
                        HStack {
                            Image(systemName: user.isPremium ? "crown.fill" : "crown")
                                .foregroundColor(.yellow)

                            VStack(alignment: .leading) {
                                Text(user.isPremium ? "Premium Member" : "Upgrade to Premium")
                                    .fontWeight(.semibold)
                                if !user.isPremium {
                                    Text("Unlimited athletes, advanced stats, and more")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Active")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }

                            Spacer()

                            if user.isPremium {
                                Text("Active")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                // Settings Section
                Section("Settings") {
                    NavigationLink(destination: SettingsView(user: user)) {
                        Label("Settings", systemImage: "gearshape")
                    }

                    NavigationLink(destination: NotificationSettingsView()) {
                        Label("Notifications", systemImage: "bell")
                    }

                    NavigationLink(destination: HelpSupportView()) {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }

                    NavigationLink(destination: AboutView()) {
                        Label("About PlayerPath", systemImage: "info.circle")
                    }
                }

                // Account Section
                Section {
                    Button("Sign Out") {
                        showingSignOutAlert = true
                    }
                    .disabled(isSigningOut)
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("More")
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                isSigningOut = true
                Task {
                    await authManager.signOut()
                    isSigningOut = false
                }
            }
        } message: {
            Text("Are you sure you want to sign out? You can always sign back in later.")
        }
    }
}

// MARK: - Subscription View

struct SubscriptionView: View {
    let user: User
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.openURL) private var openURL
    @State private var showingPaywall = false

    var body: some View {
        List {
            if user.isPremium {
                premiumActiveSection
                premiumFeaturesSection
                managementSection
            } else {
                upgradeBenefitsSection
                pricingSection
            }
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(user: user)
        }
    }

    private var premiumActiveSection: some View {
        Section {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Premium Member")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("Thank you for your support!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("Active")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .accessibilityLabel("Subscription Active")
            }
            .padding(.vertical, 8)
        }
    }

    private var premiumFeaturesSection: some View {
        Section("Your Premium Features") {
            SubscriptionFeatureRow(icon: "person.2.fill", title: "Unlimited Athletes", description: "Add as many athletes as you need")
            SubscriptionFeatureRow(icon: "chart.bar.fill", title: "Advanced Statistics", description: "Detailed performance analytics")
            SubscriptionFeatureRow(icon: "icloud.fill", title: "Cloud Storage", description: "Automatic backup and sync")
            SubscriptionFeatureRow(icon: "video.fill", title: "Unlimited Videos", description: "Record and store unlimited video clips")
            SubscriptionFeatureRow(icon: "star.fill", title: "Highlight Reels", description: "Automatically generated highlights")
        }
    }

    private var managementSection: some View {
        Section("Manage Subscription") {
            Button("Manage in App Store") {
                // Open App Store subscription management
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    openURL(url)
                }
            }
            .foregroundColor(.blue)
        }
    }

    private var upgradeBenefitsSection: some View {
        Section("Upgrade to Premium") {
            SubscriptionFeatureRow(icon: "person.2.fill", title: "Unlimited Athletes", description: "Currently limited to 3 athletes")
            SubscriptionFeatureRow(icon: "chart.bar.fill", title: "Advanced Statistics", description: "Detailed performance analytics and trends")
            SubscriptionFeatureRow(icon: "icloud.fill", title: "Cloud Storage", description: "Never lose your data with automatic backup")
            SubscriptionFeatureRow(icon: "video.fill", title: "Unlimited Videos", description: "Record and store unlimited video clips")
            SubscriptionFeatureRow(icon: "star.fill", title: "Highlight Reels", description: "Automatically generated highlight videos")
        }
    }

    private var pricingSection: some View {
        Section {
            Button(action: { showingPaywall = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Upgrade to Premium")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        Text("Unlock all features and unlimited athletes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("$9.99")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)

                        Text("per month")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

struct SubscriptionFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

