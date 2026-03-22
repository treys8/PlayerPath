//
//  AddCoachView.swift
//  PlayerPath
//
//  Extracted from CoachesView.swift
//

import SwiftUI
import SwiftData

struct AddCoachView: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var role = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var notes = ""

    enum Field: Hashable { case name, role, phone, email, notes }
    @FocusState private var focusedField: Field?

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
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .role }
                        .autocorrectionDisabled()

                    TextField("Role (optional)", text: $role)
                        .focused($focusedField, equals: .role)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .phone }
                        .autocorrectionDisabled()
                        .textContentType(.jobTitle)
                } header: {
                    Text("Coach Information")
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Phone (optional)", text: $phone)
                            .focused($focusedField, equals: .phone)
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
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .notes }
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)

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
                            .focused($focusedField, equals: .notes)
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if focusedField == .notes {
                        Button("Done") { focusedField = nil }
                            .fontWeight(.semibold)
                    } else if focusedField == .phone {
                        Button("Next") { focusedField = .email }
                    }
                }
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
        coach.needsSync = true

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
