//
//  FirstAthleteCreationView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData

struct FirstAthleteCreationView: View {
    let user: User
    @Binding var selectedAthlete: Athlete?
    let authManager: ComprehensiveAuthManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.blue.opacity(0.25), .blue.opacity(0.05)],
                                center: .center,
                                startRadius: 20,
                                endRadius: 80
                            )
                        )
                        .frame(width: 140, height: 140)
                        .blur(radius: 15)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.15), .blue.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 12) {
                    Text("Create Your First Athlete")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("Add an athlete profile to start tracking games, recording videos, and monitoring progress.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                // Add Athlete Button
                Button {
                    Haptics.medium()
                    NotificationCenter.default.post(name: Notification.Name.showAthleteSelection, object: nil)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text("Add Athlete")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Get Started")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
