//
//  CoachesView.swift
//  PlayerPath
//
//  Created by Assistant on 11/14/25.
//  Updated with proper SwiftData integration and validation
//

import SwiftUI
import SwiftData

/// View for managing coaches for an athlete
struct CoachesView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext

    @State private var showingAddCoach = false
    @State private var coachToDelete: Coach?
    @State private var showingDeleteConfirmation = false

    // Use @Query to automatically fetch coaches for this athlete
    private var athleteID: UUID

    init(athlete: Athlete) {
        self.athlete = athlete
        self.athleteID = athlete.id
    }

    // Filter coaches by athlete relationship
    private var coaches: [Coach] {
        (athlete.coaches ?? []).sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
    }

    var body: some View {
        Group {
            if coaches.isEmpty {
                EmptyCoachesView {
                    Haptics.light()
                    showingAddCoach = true
                }
            } else {
                List {
                    ForEach(coaches) { coach in
                        NavigationLink(destination: CoachDetailView(coach: coach, athlete: athlete)) {
                            CoachRow(coach: coach)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                coachToDelete = coach
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Coaches")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptics.light()
                    showingAddCoach = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCoach) {
            AddCoachView(athlete: athlete)
        }
        .alert("Delete Coach", isPresented: $showingDeleteConfirmation, presenting: coachToDelete) { coach in
            Button("Cancel", role: .cancel) {
                coachToDelete = nil
            }
            Button("Delete", role: .destructive) {
                deleteCoach(coach)
                coachToDelete = nil
            }
        } message: { coach in
            Text("Are you sure you want to remove \(coach.name) from your coaches?")
        }
    }

    private func deleteCoach(_ coach: Coach) {
        withAnimation {
            modelContext.delete(coach)
            do {
                try modelContext.save()
                Haptics.medium()
            } catch {
                print("Error deleting coach: \(error)")
                Haptics.error()
            }
        }
    }
}

// MARK: - Empty State

struct EmptyCoachesView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.badge.gearshape")
                .font(.system(size: 60))
                .foregroundStyle(.purple)

            Text("No Coaches Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add coaches to track contact info and notes")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                action()
            } label: {
                Label("Add Coach", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Coach Row

struct CoachRow: View {
    let coach: Coach

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 4) {
                Text(coach.name)
                    .font(.headline)

                if !coach.role.isEmpty {
                    Text(coach.role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !coach.phone.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.caption)
                        Text(coach.phone)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else if !coach.email.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.fill")
                            .font(.caption)
                        Text(coach.email)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Coach View

struct AddCoachView: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var role = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var notes = ""

    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emailError: String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let emailPattern = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        let regex = try? NSRegularExpression(pattern: emailPattern)
        let range = NSRange(location: 0, length: trimmed.utf16.count)

        if regex?.firstMatch(in: trimmed, range: range) == nil {
            return "Invalid email format"
        }
        return nil
    }

    private var phoneError: String? {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // Check if phone contains at least some digits
        let digits = trimmed.filter { $0.isNumber }
        if digits.count < 7 {
            return "Phone number too short"
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()

                    TextField("Role (optional)", text: $role)
                        .autocorrectionDisabled()
                        .textContentType(.jobTitle)
                } header: {
                    Text("Coach Information")
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Phone (optional)", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)

                        if let error = phoneError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Email (optional)", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)

                        if let error = emailError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Contact Information")
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes)
                            .frame(minHeight: 100)

                        if notes.isEmpty {
                            Text("Add any notes about this coach...")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }
                } header: {
                    Text("Notes (optional)")
                }
            }
            .navigationTitle("Add Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.light()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveCoach()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!isValid || emailError != nil || phoneError != nil || isSaving)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func saveCoach() {
        guard isValid else {
            errorMessage = "Please enter a coach name"
            showingError = true
            Haptics.error()
            return
        }

        guard emailError == nil && phoneError == nil else {
            errorMessage = "Please fix validation errors"
            showingError = true
            Haptics.error()
            return
        }

        isSaving = true

        let coach = Coach(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        // Set relationship
        coach.athlete = athlete

        // Insert and save
        modelContext.insert(coach)

        do {
            try modelContext.save()
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = "Failed to save coach: \(error.localizedDescription)"
            showingError = true
            isSaving = false
            Haptics.error()
        }
    }
}

// MARK: - Coach Detail View

struct CoachDetailView: View {
    let coach: Coach
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.purple)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(coach.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        if !coach.role.isEmpty {
                            Text(coach.role)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // Contact Information
            if !coach.phone.isEmpty || !coach.email.isEmpty {
                Section("Contact") {
                    if !coach.phone.isEmpty {
                        LabeledContent {
                            if let url = createPhoneURL(from: coach.phone) {
                                Link(coach.phone, destination: url)
                                    .foregroundStyle(.blue)
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
                                    .foregroundStyle(.blue)
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
                Section("Notes") {
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
            }
        }
        .navigationTitle("Coach Details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Remove Coach", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                deleteCoach()
            }
        } message: {
            Text("Are you sure you want to remove \(coach.name)?")
        }
    }

    private func deleteCoach() {
        modelContext.delete(coach)
        do {
            try modelContext.save()
            Haptics.medium()
            dismiss()
        } catch {
            print("Error deleting coach: \(error)")
            Haptics.error()
        }
    }

    /// Creates a valid phone URL, preserving international format characters
    private func createPhoneURL(from phone: String) -> URL? {
        // Keep only valid phone number characters: digits, +, (, ), -, and spaces
        let validChars = CharacterSet(charactersIn: "0123456789+()-")
        let filtered = phone.components(separatedBy: validChars.inverted).joined()

        // Remove spaces for the URL
        let urlString = "tel:\(filtered.replacingOccurrences(of: " ", with: ""))"
        return URL(string: urlString)
    }

    /// Creates a valid email URL with proper encoding
    private func createEmailURL(from email: String) -> URL? {
        // Validate basic email format first
        guard email.contains("@") && email.contains(".") else { return nil }

        // Encode the email to handle special characters
        guard let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        return URL(string: "mailto:\(encoded)")
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, Athlete.self, Coach.self, configurations: config)

    let athlete = Athlete(name: "Test Athlete")
    container.mainContext.insert(athlete)

    return NavigationStack {
        CoachesView(athlete: athlete)
    }
    .modelContainer(container)
}
