//
//  PracticesView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData

struct PracticesView: View {
    let athlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddPractice = false
    @State private var selectedPractice: Practice?
    
    var practices: [Practice] {
        athlete?.practices.sorted { $0.date > $1.date } ?? []
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if practices.isEmpty {
                    EmptyPracticesView {
                        showingAddPractice = true
                    }
                } else {
                    List {
                        ForEach(practices) { practice in
                            NavigationLink(destination: PracticeDetailView(practice: practice)) {
                                PracticeRow(practice: practice)
                            }
                        }
                        .onDelete(perform: deletePractices)
                    }
                }
            }
            .navigationTitle("Practice")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddPractice = true }) {
                        Image(systemName: "plus")
                    }
                }
                
                if !practices.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddPractice) {
            AddPracticeView(athlete: athlete)
        }
    }
    
    private func deletePractices(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let practice = practices[index]
                
                print("Deleting practice from \(practice.date)")
                
                // Remove from athlete's practices array
                if let athlete = practice.athlete,
                   let practiceIndex = athlete.practices.firstIndex(of: practice) {
                    athlete.practices.remove(at: practiceIndex)
                    print("Removed practice from athlete's array")
                }
                
                // Delete associated video clips
                for videoClip in practice.videoClips {
                    // Remove from athlete's video clips array
                    if let athlete = videoClip.athlete,
                       let clipIndex = athlete.videoClips.firstIndex(of: videoClip) {
                        athlete.videoClips.remove(at: clipIndex)
                    }
                    modelContext.delete(videoClip)
                    print("Deleted associated video clip: \(videoClip.fileName)")
                }
                
                // Delete associated notes
                for note in practice.notes {
                    modelContext.delete(note)
                    print("Deleted associated note")
                }
                
                // Delete the practice itself
                modelContext.delete(practice)
                print("Deleted practice from context")
            }
            
            do {
                try modelContext.save()
                print("Successfully saved practice deletion")
            } catch {
                print("Failed to delete practices: \(error)")
            }
        }
    }
}

struct EmptyPracticesView: View {
    let onAddPractice: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "figure.baseball")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("No Practice Sessions Yet")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Create your first practice session to start tracking training videos and notes")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onAddPractice) {
                Text("Add Practice")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

struct PracticeRow: View {
    let practice: Practice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(practice.date, formatter: DateFormatter.practiceDate)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(practice.videoClips.count) videos")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            if !practice.notes.isEmpty {
                Text("\(practice.notes.count) notes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddPracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?
    
    @State private var date = Date()
    @State private var shouldUploadVideo = false
    @State private var showingVideoRecorder = false
    @State private var createdPractice: Practice?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Practice Details") {
                    DatePicker("Practice Date", selection: $date, displayedComponents: [.date])
                }
                
                Section("Video Options") {
                    Toggle("Upload video after creating practice", isOn: $shouldUploadVideo)
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                    
                    if shouldUploadVideo {
                        HStack {
                            Image(systemName: "video.badge.plus")
                                .foregroundColor(.green)
                            Text("Video will be uploaded after practice is created")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        savePractice()
                    }
                }
            }
        }
        .sheet(isPresented: $showingVideoRecorder) {
            if let practice = createdPractice {
                VideoRecorderView(athlete: athlete, practice: practice)
            }
        }
        .onChange(of: showingVideoRecorder) { _, isShowing in
            // When video recorder is dismissed, also dismiss this view
            if !isShowing && createdPractice != nil {
                dismiss()
            }
        }
    }
    
    private func savePractice() {
        guard let athlete = athlete else { return }
        
        let practice = Practice(date: date)
        practice.athlete = athlete
        
        athlete.practices.append(practice)
        modelContext.insert(practice)
        
        do {
            try modelContext.save()
            
            if shouldUploadVideo {
                // Store the created practice and show video recorder
                createdPractice = practice
                showingVideoRecorder = true
            } else {
                dismiss()
            }
        } catch {
            print("Failed to save practice: \(error)")
        }
    }
}

struct PracticeDetailView: View {
    let practice: Practice
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingVideoRecorder = false
    @State private var showingAddNote = false
    @State private var selectedVideo: VideoClip?
    @State private var showingDeleteConfirmation = false
    
    var videoClips: [VideoClip] {
        practice.videoClips.sorted { $0.createdAt > $1.createdAt }
    }
    
    var notes: [PracticeNote] {
        practice.notes.sorted { $0.createdAt > $1.createdAt }
    }
    
    var body: some View {
        List {
            // Practice Info Section
            Section("Practice Details") {
                HStack {
                    Text("Date")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(practice.date, formatter: DateFormatter.practiceDate)
                        .foregroundColor(.secondary)
                }
            }
            
            // Actions Section
            Section("Actions") {
                Button(action: { showingVideoRecorder = true }) {
                    Label("Record Video", systemImage: "video.badge.plus")
                        .foregroundColor(.blue)
                }
                
                Button(action: { showingAddNote = true }) {
                    Label("Add Note", systemImage: "note.text.badge.plus")
                        .foregroundColor(.green)
                }
                
                Button(action: { showingDeleteConfirmation = true }) {
                    Label("Delete Practice", systemImage: "trash")
                        .foregroundColor(.red)
                }
            }
            
            // Videos Section
            Section("Videos (\(videoClips.count))") {
                if videoClips.isEmpty {
                    Text("No videos recorded yet")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(videoClips) { clip in
                        VideoClipRow(clip: clip)
                    }
                }
            }
            
            // Notes Section
            Section("Notes (\(notes.count))") {
                if notes.isEmpty {
                    Text("No notes added yet")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(notes) { note in
                        PracticeNoteRow(note: note)
                    }
                    .onDelete(perform: deleteNotes)
                }
            }
        }
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingVideoRecorder) {
            VideoRecorderView(athlete: practice.athlete, practice: practice)
        }
        .sheet(isPresented: $showingAddNote) {
            AddPracticeNoteView(practice: practice)
        }
        .alert("Delete Practice", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deletePractice()
            }
        } message: {
            Text("Are you sure you want to delete this practice session? This will also delete all associated videos and notes. This action cannot be undone.")
        }
    }
    
    private func deleteNotes(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let note = notes[index]
                modelContext.delete(note)
            }
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to delete notes: \(error)")
            }
        }
    }
    
    private func deletePractice() {
        print("Deleting practice from detail view")
        
        // Remove from athlete's practices array
        if let athlete = practice.athlete,
           let practiceIndex = athlete.practices.firstIndex(of: practice) {
            athlete.practices.remove(at: practiceIndex)
            print("Removed practice from athlete's array")
        }
        
        // Delete associated video clips
        for videoClip in practice.videoClips {
            // Remove from athlete's video clips array
            if let athlete = videoClip.athlete,
               let clipIndex = athlete.videoClips.firstIndex(of: videoClip) {
                athlete.videoClips.remove(at: clipIndex)
            }
            
            // Delete any associated play results
            if let playResult = videoClip.playResult {
                modelContext.delete(playResult)
            }
            
            modelContext.delete(videoClip)
            print("Deleted associated video clip: \(videoClip.fileName)")
        }
        
        // Delete associated notes
        for note in practice.notes {
            modelContext.delete(note)
            print("Deleted associated note")
        }
        
        // Delete the practice itself
        modelContext.delete(practice)
        print("Deleted practice from context")
        
        do {
            try modelContext.save()
            print("Successfully saved practice deletion")
            // Dismiss the view after successful deletion
            dismiss()
        } catch {
            print("Failed to delete practice: \(error)")
        }
    }
}

struct PracticeNoteRow: View {
    let note: PracticeNote
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.content)
                .font(.subheadline)
            
            Text(note.createdAt, formatter: DateFormatter.shortDateTime)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct AddPracticeNoteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let practice: Practice
    
    @State private var noteContent = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("Enter your practice notes...", text: $noteContent, axis: .vertical)
                        .lineLimit(5...10)
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveNote()
                    }
                    .disabled(noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveNote() {
        let note = PracticeNote(content: noteContent.trimmingCharacters(in: .whitespacesAndNewlines))
        note.practice = practice
        
        practice.notes.append(note)
        modelContext.insert(note)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save note: \(error)")
        }
    }
}

// Helper extension for practice date formatting
extension DateFormatter {
    static let practiceDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()
}

#Preview {
    PracticesView(athlete: nil)
}