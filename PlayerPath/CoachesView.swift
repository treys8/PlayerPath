//
//  CoachesView.swift
//  PlayerPath
//
//  Created by Assistant on 11/14/25.
//

import SwiftUI
import SwiftData

/// View for managing coaches for an athlete
struct CoachesView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingAddCoach = false
    @State private var coaches: [Coach] = []
    @State private var coachToDelete: Coach?
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        Group {
            if coaches.isEmpty {
                EmptyCoachesView {
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
        .navigationBarBackButtonHidden(false)  // Explicitly show system back button
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddCoach = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCoach) {
            AddCoachView(athlete: athlete) { newCoach in
                coaches.append(newCoach)
            }
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
        .onAppear {
            loadCoaches()
        }
    }
    
    private func loadCoaches() {
        // Load coaches from persistent storage
        // For now, this is a placeholder - you'll need to implement Coach model and relationships
        coaches = [] // Load from athlete.coaches or similar
    }
    
    private func deleteCoach(_ coach: Coach) {
        withAnimation {
            if let index = coaches.firstIndex(where: { $0.id == coach.id }) {
                coaches.remove(at: index)
            }
            // Delete from model context when Coach model is implemented
            // modelContext.delete(coach)
            // try? modelContext.save()
        }
        Haptics.medium()
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
            
            Text("Add your coaches to keep track of their contact information and notes.")
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
                
                if let role = coach.role, !role.isEmpty {
                    Text(role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let phone = coach.phone, !phone.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.caption)
                        Text(phone)
                            .font(.caption)
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
    let onSave: (Coach) -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var role = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var notes = ""
    
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    TextField("Phone (optional)", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    
                    TextField("Email (optional)", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                } header: {
                    Text("Contact Information")
                }
                
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                } header: {
                    Text("Notes (optional)")
                }
            }
            .navigationTitle("Add Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCoach()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .presentationDetents([.large])
    }
    
    private func saveCoach() {
        guard isValid else {
            errorMessage = "Please enter a coach name"
            showingError = true
            return
        }
        
        let coach = Coach(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role.isEmpty ? nil : role.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.isEmpty ? nil : phone.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.isEmpty ? nil : email.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.isEmpty ? "" : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        onSave(coach)
        Haptics.medium()
        dismiss()
    }
}

// MARK: - Coach Detail View

struct CoachDetailView: View {
    let coach: Coach
    let athlete: Athlete
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingDeleteConfirmation = false
    @State private var showingEditSheet = false
    
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
                        
                        if let role = coach.role, !role.isEmpty {
                            Text(role)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Contact Information
            if coach.phone != nil || coach.email != nil {
                Section("Contact") {
                    if let phone = coach.phone, !phone.isEmpty {
                        LabeledContent {
                            Link(phone, destination: URL(string: "tel:\(phone)")!)
                                .foregroundStyle(.blue)
                        } label: {
                            Label("Phone", systemImage: "phone.fill")
                        }
                    }
                    
                    if let email = coach.email, !email.isEmpty {
                        LabeledContent {
                            Link(email, destination: URL(string: "mailto:\(email)")!)
                                .foregroundStyle(.blue)
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
                    showingDeleteConfirmation = true
                } label: {
                    Label("Remove Coach", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Coach Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditSheet = true
                } label: {
                    Text("Edit")
                }
            }
        }
        .alert("Remove Coach", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                // Delete coach and dismiss
                dismiss()
            }
        } message: {
            Text("Are you sure you want to remove \(coach.name) from your coaches?")
        }
    }
}

// MARK: - Temporary Coach Model
// This is a temporary model until you implement it in your main Models.swift file

struct Coach: Identifiable {
    let id: UUID
    var name: String
    var role: String?
    var phone: String?
    var email: String?
    var notes: String
    
    init(name: String, role: String? = nil, phone: String? = nil, email: String? = nil, notes: String = "") {
        self.id = UUID()
        self.name = name
        self.role = role
        self.phone = phone
        self.email = email
        self.notes = notes
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, Athlete.self, configurations: config)
    
    let athlete = Athlete(name: "Test Athlete")
    container.mainContext.insert(athlete)
    
    return NavigationStack {
        CoachesView(athlete: athlete)
    }
    .modelContainer(container)
}
