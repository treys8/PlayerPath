//
//  CoachDetailView.swift
//  PlayerPath
//
//  Extracted from CoachesView.swift
//

import SwiftUI
import SwiftData

struct CoachDetailView: View {
    let coach: Coach
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private var folderManager: SharedFolderManager { .shared }

    @State private var showingDeleteConfirmation = false
    @State private var showingInviteToFolder = false

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.brandNavy)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(coach.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        if !coach.role.isEmpty {
                            Text(coach.role)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Connection status
                        HStack(spacing: 6) {
                            Image(systemName: coach.hasFirebaseAccount ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                            Text(coach.connectionStatus)
                                .font(.caption)
                        }
                        .foregroundStyle(coachStatusColor(for: coach.connectionStatusColor))
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }

            // Firebase Connection Status
            if coach.hasFirebaseAccount {
                Section(header: Text("App Access").smallCapsLabel()) {
                    LabeledContent {
                        Text("Active")
                            .foregroundStyle(.green)
                    } label: {
                        Label("Account Status", systemImage: "person.fill.checkmark")
                    }

                    if let acceptedAt = coach.invitationAcceptedAt {
                        LabeledContent {
                            Text(acceptedAt.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Connected Since", systemImage: "calendar")
                        }
                    }
                }
            } else if coach.invitationSentAt != nil {
                Section(header: Text("App Access").smallCapsLabel()) {
                    LabeledContent {
                        Text(coach.connectionStatus)
                            .foregroundStyle(coachStatusColor(for: coach.connectionStatusColor))
                    } label: {
                        Label("Invitation Status", systemImage: "envelope")
                    }

                    if let sentAt = coach.invitationSentAt {
                        LabeledContent {
                            Text(sentAt.formatted(.relative(presentation: .named)))
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Sent", systemImage: "clock")
                        }
                    }
                }
            }

            // Shared Folders
            if coach.hasFolderAccess {
                Section(header: Text("Shared Folders").smallCapsLabel()) {
                    ForEach(coach.sharedFolderIDs, id: \.self) { folderID in
                        if let folder = folderManager.athleteFolders.first(where: { $0.id == folderID }) {
                            NavigationLink(destination: AthleteFolderDetailView(folder: folder)) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.brandNavy)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        if let count = folder.videoCount, count > 0 {
                                            Text("\(count) video\(count == 1 ? "" : "s")")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        } else {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.brandNavy)
                                Text("Folder")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // Contact Information
            if !coach.phone.isEmpty || !coach.email.isEmpty {
                Section(header: Text("Contact").smallCapsLabel()) {
                    if !coach.phone.isEmpty {
                        LabeledContent {
                            if let url = createPhoneURL(from: coach.phone) {
                                Link(coach.phone, destination: url)
                                    .foregroundColor(.brandNavy)
                            } else {
                                Text(coach.phone)
                            }
                        } label: {
                            Label("Phone", systemImage: "phone.fill")
                        }
                    }

                    if !coach.email.isEmpty {
                        LabeledContent {
                            if let url = createEmailURL(from: coach.email) {
                                Link(coach.email, destination: url)
                                    .foregroundColor(.brandNavy)
                            } else {
                                Text(coach.email)
                            }
                        } label: {
                            Label("Email", systemImage: "envelope.fill")
                        }
                    }
                }
            }

            // Notes
            if !coach.notes.isEmpty {
                Section(header: Text("Notes").smallCapsLabel()) {
                    Text(coach.notes)
                }
            }

            // Actions
            Section {
                Button(role: .destructive) {
                    Haptics.warning()
                    showingDeleteConfirmation = true
                } label: {
                    Label("Remove Coach", systemImage: "trash")
                }
                .labelStyle(DestructiveRowLabelStyle())
            }
        }
        .ppDetailBackground()
        .navigationTitle("Coach Details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Remove Coach", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                Haptics.heavy()
                deleteCoach()
            }
        } message: {
            Text("Are you sure you want to remove \(coach.name)?")
        }
        .task {
            if folderManager.athleteFolders.isEmpty, let userID = authManager.userID {
                try? await folderManager.loadAthleteFolders(athleteID: userID)
            }
        }
    }

    private func deleteCoach() {
        // Capture Firestore identifiers before deletion clears the object
        let firebaseCoachID = coach.firebaseCoachID
        let sharedFolderIDs = coach.sharedFolderIDs
        let coachFirestoreId = coach.firestoreId
        let userId = athlete.user?.firebaseAuthUid ?? athlete.user?.id.uuidString
        let athleteFirestoreId = athlete.firestoreId
        let coachEmail = coach.email

        modelContext.delete(coach)
        do {
            try modelContext.save()
            Haptics.medium()
            dismiss()
        } catch {
            // The remote revoke below proceeds regardless (revoke-first design,
            // see CoachRemovalService), so the coach is leaving either way.
            // Dismiss so we don't keep rendering this detail view against a
            // pending-delete coach object. The pending local delete commits on
            // the next successful save or on relaunch.
            ErrorHandlerService.shared.handle(error, context: "CoachDetailView.deleteCoach", showAlert: true)
            dismiss()
        }

        Task {
            await CoachRemovalService.revokeRemoteAccess(
                firebaseCoachID: firebaseCoachID,
                sharedFolderIDs: sharedFolderIDs,
                userID: userId,
                athleteFirestoreID: athleteFirestoreId,
                coachFirestoreID: coachFirestoreId,
                coachEmail: coachEmail.isEmpty ? nil : coachEmail
            )
        }
    }

    /// Creates a valid phone URL, preserving international format characters
    private func createPhoneURL(from phone: String) -> URL? {
        let validChars = CharacterSet(charactersIn: "0123456789+()-")
        let filtered = phone.components(separatedBy: validChars.inverted).joined()
        return URL(string: "tel:\(filtered)")
    }

    /// Creates a valid email URL with proper encoding
    private func createEmailURL(from email: String) -> URL? {
        guard email.contains("@") && email.contains(".") else { return nil }
        guard let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "mailto:\(encoded)")
    }
}
