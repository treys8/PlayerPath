//
//  ProfileView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Profile View (Main "More" Tab Root)

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
    @State private var showingPaywall = false
    
    // Premium limits
    private let freeAthleteLimit = 3

    var body: some View {
        List {
            userProfileSection
            athletesSection
            settingsSection
            accountSection
        }
        .tabRootNavigationBar(title: "Profile & Settings")
        .sheet(isPresented: $showingAddAthlete) {
            AddAthleteView(user: user, selectedAthlete: $selectedAthlete, isFirstAthlete: user.athletes.isEmpty)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(user: user)
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
    
    private var canAddMoreAthletes: Bool {
        user.isPremium || user.athletes.count < freeAthleteLimit
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
            NavigationLink(destination: AthleteManagementView(user: user, selectedAthlete: $selectedAthlete)) {
                Label("Manage Athletes", systemImage: "person.2.fill")
            }
            
            ForEach(sortedAthletes) { athlete in
                AthleteProfileRow(
                    athlete: athlete,
                    isSelected: athlete.id == selectedAthlete?.id
                ) {
                    selectedAthlete = athlete
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .onDelete { offsets in
                if let index = offsets.first, index < sortedAthletes.count {
                    athletePendingDelete = sortedAthletes[index]
                    showingDeleteAthleteAlert = true
                }
            }

            Button(action: {
                if canAddMoreAthletes {
                    showingAddAthlete = true
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    showingPaywall = true
                }
            }) {
                Label("Add Athlete", systemImage: "person.badge.plus")
            }
            .tint(.blue)
            
            if !user.isPremium && user.athletes.count >= freeAthleteLimit {
                HStack {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text("Upgrade to Premium for unlimited athletes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if !user.isPremium {
                Text("\(user.athletes.count) of \(freeAthleteLimit) free athletes used")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var settingsSection: some View {
        Section("Settings") {
            NavigationLink(destination: SettingsView(user: user)) {
                Label("Settings", systemImage: "gearshape")
            }

            NavigationLink(destination: SecuritySettingsView(user: user)) {
                Label("Security Settings", systemImage: "lock.shield")
            }

            NavigationLink(destination: NotificationSettingsView()) {
                Label("Notifications", systemImage: "bell")
            }

            #if DEBUG
            // CloudKit sync testing - monitors iCloud availability and sync status
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
            deleteErrorMessage = "Failed to delete athlete: \(error.localizedDescription)"
            showDeleteError = true
        }
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

struct SecuritySettingsView: View {
    let user: User
    @EnvironmentObject var authManager: ComprehensiveAuthManager
    @State private var showingDeleteAccountAlert = false
    @State private var showingChangePasswordSheet = false
    @State private var showComingSoonAlert = false
    @State private var comingSoonFeature = ""
    
    var body: some View {
        Form {
            Section("Account Information") {
                HStack {
                    Text("User ID")
                    Spacer()
                    Text(user.id.uuidString.prefix(8))
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
                
                HStack {
                    Text("Email")
                    Spacer()
                    Text(user.email)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Security") {
                Button {
                    comingSoonFeature = "Change Password"
                    showComingSoonAlert = true
                } label: {
                    Label("Change Password", systemImage: "key.fill")
                        .foregroundColor(.primary)
                }
                .disabled(true)
                .opacity(0.6)
                
                Button {
                    comingSoonFeature = "Two-Factor Authentication"
                    showComingSoonAlert = true
                } label: {
                    Label("Two-Factor Authentication", systemImage: "lock.shield.fill")
                        .foregroundColor(.primary)
                }
                .disabled(true)
                .opacity(0.6)
            }
            
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Additional security features are coming soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Section("Data Management") {
                Button {
                    comingSoonFeature = "Export Account Data"
                    showComingSoonAlert = true
                } label: {
                    Label("Export Account Data", systemImage: "square.and.arrow.up")
                        .foregroundColor(.primary)
                }
                .disabled(true)
                .opacity(0.6)
            }
            
            Section {
                Button(role: .destructive) {
                    showingDeleteAccountAlert = true
                } label: {
                    Label("Delete Account", systemImage: "trash.fill")
                }
                .disabled(true)
                .opacity(0.6)
            } footer: {
                Text("Account deletion is coming soon. This will permanently delete your account and all associated data.")
                    .font(.caption)
            }
        }
        .alert("Coming Soon", isPresented: $showComingSoonAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(comingSoonFeature) will be available in a future update.")
        }
        .alert("Delete Account", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                // Handle account deletion
            }
        } message: {
            Text("This action cannot be undone. All your data will be permanently deleted.")
        }
    }
}

struct SettingsView: View {
    let user: User
    @State private var notificationsEnabled = true
    @State private var dataBackupEnabled = true
    @State private var showComingSoonAlert = false
    @State private var comingSoonFeature = ""

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
            }

            Section("Preferences") {
                Toggle("Push Notifications", isOn: $notificationsEnabled)
                    .disabled(true)
                    .opacity(0.6)
                
                Toggle("Auto Backup Data", isOn: $dataBackupEnabled)
                    .disabled(true)
                    .opacity(0.6)
                
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Notification and backup preferences are coming soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // Removed unimplemented features for now:
            // - Change Password
            // - Export Data  
            // - Delete Account
        }
        .alert("Coming Soon", isPresented: $showComingSoonAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(comingSoonFeature) will be available in a future update.")
        }
    }
}

struct EditAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var email: String
    let user: User
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    init(user: User) {
        self.user = user
        _username = State(initialValue: user.username)
        _email = State(initialValue: user.email)
    }
    
    private var isValidEmail: Bool {
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private var canSave: Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedUsername.isEmpty && !trimmedEmail.isEmpty && isValidEmail
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
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                
                if !email.isEmpty && !isValidEmail {
                    Label("Please enter a valid email address", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Section {
                Button("Save Changes") {
                    save()
                }
                .disabled(!canSave)
            }
        }
        .alert("Unable to Save", isPresented: $showSaveError) {
            Button("OK") { }
        } message: {
            Text(saveErrorMessage.isEmpty ? "Please try again in a moment." : saveErrorMessage)
        }
    }

    private func save() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedUsername.isEmpty else {
            saveErrorMessage = "Username cannot be empty"
            showSaveError = true
            return
        }
        
        guard isValidEmail else {
            saveErrorMessage = "Please enter a valid email address"
            showSaveError = true
            return
        }
        
        user.username = trimmedUsername
        user.email = trimmedEmail
        
        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            print("Failed to save user: \(error)")
            saveErrorMessage = "Failed to save changes: \(error.localizedDescription)"
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
                if let emailURL = URL(string: "mailto:support@playerpath.app") {
                    Link("Email Support", destination: emailURL)
                }
                if let websiteURL = URL(string: "https://playerpath.app") {
                    Link("Visit Website", destination: websiteURL)
                }
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

// MARK: - Athlete Management View

struct AthleteManagementView: View {
    let user: User
    @Binding var selectedAthlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddAthlete = false
    @State private var athletePendingDelete: Athlete?
    @State private var showingDeleteAthleteAlert = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    
    private var sortedAthletes: [Athlete] {
        user.athletes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    var body: some View {
        List {
            Section {
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
            }
            
            Section {
                Button(action: { showingAddAthlete = true }) {
                    Label("Add Athlete", systemImage: "person.badge.plus")
                }
                .tint(.blue)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAddAthlete) {
            AddAthleteView(user: user, selectedAthlete: $selectedAthlete, isFirstAthlete: user.athletes.isEmpty)
        }
        .alert("Delete Athlete", isPresented: $showingDeleteAthleteAlert) {
            Button("Cancel", role: .cancel) { athletePendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let athlete = athletePendingDelete {
                    delete(athlete: athlete)
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
            deleteErrorMessage = "Failed to delete athlete: \(error.localizedDescription)"
            showDeleteError = true
        }
    }
}

#Preview {
    ProfileView(user: User(username: "test", email: "test@example.com"), selectedAthlete: .constant(nil))
        .environmentObject(ComprehensiveAuthManager())
}

// MARK: - Profile Detail View

/// Detailed profile view that shows user information and athlete management
struct ProfileDetailView: View {
    let user: User
    @Binding var selectedAthlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingAddAthlete = false
    @State private var athletePendingDelete: Athlete?
    @State private var showingDeleteAthleteAlert = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var showingPaywall = false
    
    // Premium limits
    private let freeAthleteLimit = 3
    
    private var sortedAthletes: [Athlete] {
        user.athletes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private var canAddMoreAthletes: Bool {
        user.isPremium || user.athletes.count < freeAthleteLimit
    }
    
    var body: some View {
        List {
            // User Profile Section
            Section {
                HStack(spacing: 15) {
                    EditableProfileImageView(user: user, size: 80) {
                        do {
                            try modelContext.save()
                        } catch {
                            print("Failed to save profile image: \(error)")
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
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
                }
                .padding(.vertical, 8)
            }
            
            // Athletes Section
            Section("Athletes") {
                ForEach(sortedAthletes) { athlete in
                    Button {
                        selectedAthlete = athlete
                    } label: {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(athlete.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                if let created = athlete.createdAt {
                                    Text("Created \(created, format: .dateTime.day().month().year())")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if athlete.id == selectedAthlete?.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    if let index = offsets.first, index < sortedAthletes.count {
                        athletePendingDelete = sortedAthletes[index]
                        showingDeleteAthleteAlert = true
                    }
                }
                
                Button {
                    if canAddMoreAthletes {
                        showingAddAthlete = true
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    Label("Add Athlete", systemImage: "person.badge.plus")
                }
                .tint(.blue)
                
                if !user.isPremium && user.athletes.count >= freeAthleteLimit {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("Upgrade to Premium for unlimited athletes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else if !user.isPremium {
                    Text("\(user.athletes.count) of \(freeAthleteLimit) free athletes used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAddAthlete) {
            AddAthleteView(user: user, selectedAthlete: $selectedAthlete, isFirstAthlete: user.athletes.isEmpty)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(user: user)
        }
        .alert("Delete Athlete", isPresented: $showingDeleteAthleteAlert) {
            Button("Cancel", role: .cancel) { athletePendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let athlete = athletePendingDelete {
                    delete(athlete: athlete)
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
            deleteErrorMessage = "Failed to delete athlete: \(error.localizedDescription)"
            showDeleteError = true
        }
    }
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
            // Profile Header (tappable to view/edit profile)
            Section {
                NavigationLink(destination: ProfileDetailView(user: user, selectedAthlete: $selectedAthlete)) {
                    HStack(spacing: 12) {
                        EditableProfileImageView(user: user, size: 60) {
                            do {
                                try modelContext.save()
                            } catch {
                                print("Failed to save profile image: \(error)")
                            }
                        }
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.username)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            
            // Organization section with Seasons and Coaches
            if let athlete = selectedAthlete {
                Section("Organization") {
                    NavigationLink(destination: SeasonsView(athlete: athlete)) {
                        Label("Seasons", systemImage: "calendar")
                    }
                    
                    NavigationLink(destination: CoachesView(athlete: athlete)) {
                        Label("Coaches", systemImage: "person.3.fill")
                    }
                }
            }

            // Subscription Section
            Section("Subscription") {
                NavigationLink(destination: SubscriptionView(user: user)) {
                    HStack(spacing: 12) {
                        Image(systemName: user.isPremium ? "crown.fill" : "crown")
                            .font(.title3)
                            .foregroundColor(.yellow)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.isPremium ? "Premium Member" : "Upgrade to Premium")
                                .fontWeight(.semibold)
                            if !user.isPremium {
                                Text("Unlock all features")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if user.isPremium {
                            Text("Active")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                        }
                    }
                }
            }

            // Settings Section
            Section("Settings") {
                NavigationLink(destination: SettingsView(user: user)) {
                    Label("App Settings", systemImage: "gearshape")
                }
                
                NavigationLink(destination: VideoRecordingSettingsView()) {
                    Label("Video Recording", systemImage: "video.fill")
                }

                NavigationLink(destination: SecuritySettingsView(user: user)) {
                    Label("Account & Security", systemImage: "lock.shield")
                }

                NavigationLink(destination: NotificationSettingsView()) {
                    Label("Notifications", systemImage: "bell")
                }
            }
            
            // Support Section
            Section("Support") {
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

