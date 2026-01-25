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
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                Text("Create Your First Athlete")
                    .font(.title2).bold()
                Text("Tap the + button to add your first athlete from the selection screen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button {
                    // Fallback: present the add athlete sheet by posting selection request
                    NotificationCenter.default.post(name: Notification.Name.showAthleteSelection, object: nil)
                } label: {
                    Label("Add Athlete", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Get Started")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
