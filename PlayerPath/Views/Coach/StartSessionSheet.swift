//
//  StartSessionSheet.swift
//  PlayerPath
//
//  Athlete picker for starting a live instruction session.
//  Coach selects 1+ athletes, then starts the session.
//

import SwiftUI
import FirebaseAuth

struct StartSessionSheet: View {
    let onSessionStarted: (String) -> Void
    var onInviteAthlete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    @State private var selectedAthleteIDs: Set<String> = []
    @State private var isStarting = false
    @State private var errorMessage: String?

    private var availableAthletes: [(athleteID: String, athleteName: String, folderID: String)] {
        guard let coachID = authManager.userID else { return [] }
        return CoachUploadableAthletesHelper.availableAthletes(coachID: coachID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableAthletes.isEmpty {
                    noAthletesView
                } else {
                    athleteList
                }
            }
            .navigationTitle("Start Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isStarting)
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Athlete List

    private var athleteList: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(availableAthletes, id: \.athleteID) { athlete in
                        Button {
                            toggleSelection(athlete.athleteID)
                        } label: {
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(Color.brandNavy.opacity(0.1))
                                        .frame(width: 40, height: 40)
                                    Text(String(athlete.athleteName.prefix(1)).uppercased())
                                        .font(.headline)
                                        .foregroundColor(.brandNavy)
                                }
                                .accessibilityHidden(true)

                                Text(athlete.athleteName)
                                    .font(.body)
                                    .foregroundColor(.primary)

                                Spacer()

                                if selectedAthleteIDs.contains(athlete.athleteID) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.brandNavy)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.gray)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .accessibilityAddTraits(selectedAthleteIDs.contains(athlete.athleteID) ? .isSelected : [])
                    }
                } header: {
                    Text("Select Athletes")
                } footer: {
                    Text("Choose which athletes you're working with in this session.")
                }
            }

            // Start button
            Button {
                startSession()
            } label: {
                HStack {
                    if isStarting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isStarting ? "Starting..." : "Start Session")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(selectedAthleteIDs.isEmpty ? Color.gray : Color.brandNavy)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(selectedAthleteIDs.isEmpty || isStarting)
            .padding()
        }
    }

    // MARK: - No Athletes

    private var noAthletesView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("No Athletes Available")
                .font(.title3)
                .fontWeight(.semibold)
            Text("You need upload permission on at least one athlete's folder to start a session.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if onInviteAthlete != nil {
                Button {
                    dismiss()
                    onInviteAthlete?()
                } label: {
                    Label("Invite an Athlete", systemImage: "person.badge.plus")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.brandNavy)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ athleteID: String) {
        if selectedAthleteIDs.contains(athleteID) {
            selectedAthleteIDs.remove(athleteID)
        } else {
            selectedAthleteIDs.insert(athleteID)
        }
        Haptics.light()
    }

    private func startSession() {
        guard let coachID = authManager.userID else { return }
        let currentUser = Auth.auth().currentUser
        let coachName = currentUser?.displayName ?? currentUser?.email ?? "Coach"

        let selected = availableAthletes.filter { selectedAthleteIDs.contains($0.athleteID) }
        guard !selected.isEmpty else { return }

        isStarting = true

        Task {
            do {
                let sessionID = try await CoachSessionManager.shared.createSession(
                    coachID: coachID,
                    coachName: coachName,
                    athletes: selected,
                    authManager: authManager
                )
                Haptics.success()
                dismiss()
                onSessionStarted(sessionID)
            } catch {
                errorMessage = "Failed to start session: \(error.localizedDescription)"
                ErrorHandlerService.shared.handle(error, context: "StartSessionSheet.startSession", showAlert: false)
                isStarting = false
            }
        }
    }
}
