//
//  StartSessionSheet.swift
//  PlayerPath
//
//  Athlete picker for starting or scheduling an instruction session.
//  Coach selects 1+ athletes, then starts now or schedules for later.
//

import SwiftUI

struct StartSessionSheet: View {
    let onSessionStarted: (String) -> Void
    var onInviteAthlete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    @State private var selectedAthleteIDs: Set<String> = []
    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var sessionMode: SessionMode = .startNow
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var sessionNotes = ""

    private enum SessionMode: String, CaseIterable {
        case startNow = "Start Now"
        case schedule = "Schedule"
    }

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
            .navigationTitle(sessionMode == .startNow ? "Start Session" : "Schedule Session")
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
                // Mode picker
                Section {
                    Picker("Session Type", selection: $sessionMode) {
                        ForEach(SessionMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                // Scheduling options
                if sessionMode == .schedule {
                    Section {
                        DatePicker(
                            "Date & Time",
                            selection: $scheduledDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )

                        TextField("Notes (optional)", text: $sessionNotes, axis: .vertical)
                            .lineLimit(2...4)
                    } header: {
                        Text("Session Details")
                    }
                }

                // Athlete selection
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

            // Action button
            Button {
                if sessionMode == .startNow {
                    startSession()
                } else {
                    scheduleSession()
                }
            } label: {
                HStack {
                    if isStarting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(actionButtonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(selectedAthleteIDs.isEmpty ? Color.gray : sessionMode == .startNow ? Color.brandNavy : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(selectedAthleteIDs.isEmpty || isStarting)
            .padding()
        }
    }

    private var actionButtonTitle: String {
        if isStarting {
            return sessionMode == .startNow ? "Starting..." : "Scheduling..."
        }
        return sessionMode == .startNow ? "Start Session" : "Schedule Session"
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

    private var resolvedCoachName: String {
        authManager.userDisplayName ?? authManager.userEmail ?? "Coach"
    }

    private func startSession() {
        guard let coachID = authManager.userID else { return }

        let selected = availableAthletes.filter { selectedAthleteIDs.contains($0.athleteID) }
        guard !selected.isEmpty else { return }

        isStarting = true

        Task {
            do {
                let sessionID = try await CoachSessionManager.shared.createSession(
                    coachID: coachID,
                    coachName: resolvedCoachName,
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

    private func scheduleSession() {
        guard let coachID = authManager.userID else { return }

        let selected = availableAthletes.filter { selectedAthleteIDs.contains($0.athleteID) }
        guard !selected.isEmpty else { return }

        isStarting = true

        Task {
            do {
                let notes = sessionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await CoachSessionManager.shared.scheduleSession(
                    coachID: coachID,
                    coachName: resolvedCoachName,
                    athletes: selected,
                    scheduledDate: scheduledDate,
                    notes: notes.isEmpty ? nil : notes,
                    authManager: authManager
                )
                Haptics.success()
                dismiss()
            } catch {
                errorMessage = "Failed to schedule session: \(error.localizedDescription)"
                ErrorHandlerService.shared.handle(error, context: "StartSessionSheet.scheduleSession", showAlert: false)
                isStarting = false
            }
        }
    }
}
