//
//  ProfileView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    let user: User
    @Binding var selectedAthlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddAthlete = false
    @State private var showingSettings = false
    @State private var showingPaywall = false
    
    var body: some View {
        NavigationStack {
            List {
                // User Profile Section
                Section {
                    UserProfileHeader(user: user)
                }
                
                // Athletes Section
                Section("Athletes") {
                    ForEach(user.athletes) { athlete in
                        AthleteProfileRow(
                            athlete: athlete,
                            isSelected: athlete.id == selectedAthlete?.id
                        ) {
                            selectedAthlete = athlete
                        }
                    }
                    .onDelete(perform: deleteAthletes)
                    
                    Button(action: { showingAddAthlete = true }) {
                        Label("Add Athlete", systemImage: "person.badge.plus")
                            .foregroundColor(.blue)
                    }
                }
                
                // Premium Section
                Section("Premium Features") {
                    if user.isPremium {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                            Text("Premium Member")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("Active")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    } else {
                        Button(action: { showingPaywall = true }) {
                            HStack {
                                Image(systemName: "crown")
                                    .foregroundColor(.yellow)
                                
                                VStack(alignment: .leading) {
                                    Text("Upgrade to Premium")
                                        .fontWeight(.semibold)
                                    Text("Unlimited athletes, advanced stats, and more")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                        .foregroundColor(.primary)
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
                        signOut()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Profile")
        }
        .sheet(isPresented: $showingAddAthlete) {
            AddAthleteView(user: user, selectedAthlete: $selectedAthlete)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(user: user)
        }
    }
    
    private func deleteAthletes(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let athlete = user.athletes[index]
                
                // If deleting the selected athlete, select another or none
                if athlete.id == selectedAthlete?.id {
                    selectedAthlete = user.athletes.first { $0.id != athlete.id }
                }
                
                modelContext.delete(athlete)
            }
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to delete athlete: \(error)")
            }
        }
    }
    
    private func signOut() {
        // In a real app, you'd clear authentication tokens, etc.
        // For now, we'll just clear the user data
        modelContext.delete(user)
        try? modelContext.save()
    }
}

struct UserProfileHeader: View {
    let user: User
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(user.username)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(user.email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Member since \(user.createdAt, formatter: DateFormatter.yearOnly)")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                        Text("\(athlete.games.count) games")
                        Text("•")
                        Text("\(athlete.videoClips.count) clips")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
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

struct NotificationSettingsView: View {
    @State private var gameReminders = true
    @State private var weeklyStats = true
    @State private var achievements = true
    
    var body: some View {
        Form {
            Section("Game Notifications") {
                Toggle("Game Reminders", isOn: $gameReminders)
                Toggle("Live Game Updates", isOn: $gameReminders)
            }
            
            Section("Statistics") {
                Toggle("Weekly Statistics", isOn: $weeklyStats)
                Toggle("Monthly Reports", isOn: $weeklyStats)
            }
            
            Section("Achievements") {
                Toggle("New Achievements", isOn: $achievements)
                Toggle("Milestone Alerts", isOn: $achievements)
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
        NavigationStack {
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
                        PremiumFeatureRow(
                            icon: "person.3.fill",
                            title: "Unlimited Athletes",
                            description: "Track multiple players"
                        )
                        
                        PremiumFeatureRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Advanced Statistics",
                            description: "Detailed analytics and trends"
                        )
                        
                        PremiumFeatureRow(
                            icon: "icloud.and.arrow.up",
                            title: "Cloud Backup",
                            description: "Never lose your data"
                        )
                        
                        PremiumFeatureRow(
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
                    
                    Button(action: upgradeToPremium) {
                        Text("Start Premium")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    
                    Text("Cancel anytime • 7-day free trial")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Later") {
                        dismiss()
                    }
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

struct PremiumFeatureRow: View {
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

// Helper extension for date formatting
extension DateFormatter {
    static let yearOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()
}

#Preview {
    ProfileView(user: User(username: "test", email: "test@example.com"), selectedAthlete: .constant(nil))
}