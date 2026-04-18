//
//  StartSessionSheet.swift
//  PlayerPath
//
//  Athlete picker for creating an instruction session.
//  Coach selects 1+ athletes, optionally sets a date/notes, then creates.
//  The session appears on the dashboard where the coach can "Go Live."
//

import SwiftUI

struct StartSessionSheet: View {
    var onInviteAthlete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    @State private var selectedAthleteIDs: Set<String> = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showDatePicker = false
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var sessionNotes = ""

    /// Deduplicated athletes the coach can upload to, preferring "lessons" folders
    /// when both a games and lessons folder exist for the same athlete.
    private var availableAthletes: [(athleteID: String, athleteName: String, folderID: String)] {
        guard let coachID = authManager.userID else { return [] }
        let uploadableFolders = SharedFolderManager.shared.coachFolders.filter { folder in
            folder.getPermissions(for: coachID)?.canUpload == true
        }

        var athleteFolders: [String: SharedFolder] = [:]
        for folder in uploadableFolders {
            guard folder.id != nil else { continue }
            // Prefer per-athlete UUID (one key per real athlete); fall back to account UID for legacy rows.
            let key = folder.athleteUUID ?? folder.ownerAthleteID
            if let existing = athleteFolders[key] {
                if folder.folderType == "lessons" && existing.folderType != "lessons" {
                    athleteFolders[key] = folder
                }
            } else {
                athleteFolders[key] = folder
            }
        }

        return athleteFolders.compactMap { key, folder in
            guard let folderID = folder.id else { return nil }
            return (athleteID: key, athleteName: folder.ownerAthleteName ?? "Athlete", folderID: folderID)
        }
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
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
            }
            .alert("Unable to Start Session", isPresented: .init(
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

                // Optional details
                Section {
                    Toggle("Set Date & Time", isOn: $showDatePicker)

                    if showDatePicker {
                        DatePicker(
                            "Date & Time",
                            selection: $scheduledDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    TextField("Notes (optional)", text: $sessionNotes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Details")
                }
            }

            // Create button
            Button {
                createSession()
            } label: {
                HStack {
                    if isCreating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isCreating ? "Creating..." : "Create Session")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(selectedAthleteIDs.isEmpty ? Color.gray : Color.brandNavy)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(selectedAthleteIDs.isEmpty || isCreating)
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

    private func createSession() {
        guard let coachID = authManager.userID else { return }
        let coachName = authManager.userDisplayName ?? authManager.userEmail ?? "Coach"

        let selected = availableAthletes.filter { selectedAthleteIDs.contains($0.athleteID) }
        guard !selected.isEmpty else { return }

        isCreating = true

        Task {
            do {
                let notes = sessionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await CoachSessionManager.shared.scheduleSession(
                    coachID: coachID,
                    coachName: coachName,
                    athletes: selected,
                    scheduledDate: showDatePicker ? scheduledDate : nil,
                    notes: notes.isEmpty ? nil : notes,
                    authManager: authManager
                )
                Haptics.success()
                dismiss()
            } catch {
                errorMessage = "Failed to create session: \(error.localizedDescription)"
                ErrorHandlerService.shared.handle(error, context: "StartSessionSheet.createSession", showAlert: false)
                isCreating = false
            }
        }
    }
}
