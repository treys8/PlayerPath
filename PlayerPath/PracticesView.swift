//
//  PracticesView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import os
import UIKit

private let log = Logger(subsystem: "com.playerpath.app", category: "Practices")

struct PracticesView: View {
    let athlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddPractice = false
    @State private var selectedPractice: Practice?
    @State private var searchText: String = ""
    
    var practices: [Practice] {
        athlete?.practices.sorted { (lhs, rhs) in
            let l = lhs.date ?? .distantPast
            let r = rhs.date ?? .distantPast
            return l > r
        } ?? []
    }
    
    var filteredPractices: [Practice] {
        let items: [Practice] = practices
        let trimmed: String = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        let q: String = trimmed.lowercased()
        return items.filter { practice in
            matchesSearch(practice, query: q)
        }
    }
    
    private func matchesSearch(_ practice: Practice, query q: String) -> Bool {
        // Precompute components to help the type-checker and keep the filter closure small
        let dateValue: Date = practice.date ?? .distantPast
        let dateString: String = dateValue
            .formatted(date: .abbreviated, time: .omitted)
            .lowercased()

        let videoCount: Int = practice.videoClips.count
        let noteCount: Int = practice.notes.count

        let videoCountString: String = String(videoCount)
        let noteCountString: String = String(noteCount)

        let matchesDate: Bool = dateString.contains(q)
        let matchesVideoCount: Bool = videoCountString.contains(q)
        let matchesNoteCount: Bool = noteCountString.contains(q)

        return matchesDate || matchesVideoCount || matchesNoteCount
    }
    
    var body: some View {
        Group {
            VStack {
                if filteredPractices.isEmpty {
                    EmptyPracticesView {
                        showingAddPractice = true
                    }
                } else {
                    List {
                        ForEach(filteredPractices, id: \.persistentModelID) { practice in
                            PracticeListRow(practice: practice) {
                                deleteSinglePractice(practice)
                            }
                        }
                        .onDelete { offsets in deletePracticesFromFiltered(offsets: offsets) }
                    }
                }
            }
        }
        .navigationTitle("Practices")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .animation(.default, value: filteredPractices.count)
        .refreshable {
            // TODO: hook up sync or reload
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddPractice = true }) {
                    Image(systemName: "plus")
                        .accessibilityLabel("Add Practice")
                }
            }
            
            if !practices.isEmpty {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showingAddPractice) {
            AddPracticeView(athlete: athlete)
        }
    }
    
    private func deletePractices(offsets: IndexSet) {
        withAnimation {
            let idsToDelete = offsets.map { practices[$0].persistentModelID }
            for id in idsToDelete {
                if let practice = practices.first(where: { $0.persistentModelID == id }) {
                    // Remove from athlete's practices array
                    if let athlete = practice.athlete,
                       let practiceIndex = athlete.practices.firstIndex(of: practice) {
                        athlete.practices.remove(at: practiceIndex)
                        log.debug("Removed practice from athlete's array")
                    }

                    // Delete associated video clips
                    for videoClip in practice.videoClips {
                        if let athlete = videoClip.athlete,
                           let clipIndex = athlete.videoClips.firstIndex(of: videoClip) {
                            athlete.videoClips.remove(at: clipIndex)
                        }
                        modelContext.delete(videoClip)
                        log.debug("Deleted associated video clip: \(videoClip.fileName)")
                    }

                    // Delete associated notes
                    for note in practice.notes {
                        modelContext.delete(note)
                        log.debug("Deleted associated note")
                    }

                    modelContext.delete(practice)
                    log.info("Deleted practice from context")
                }
            }

            do {
                try modelContext.save()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                log.info("Successfully saved practice deletion")
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                log.error("Failed to delete practices: \(error.localizedDescription)")
            }
        }
    }
    
    private func deleteSinglePractice(_ practice: Practice) {
        withAnimation {
            // Remove from athlete's practices array
            if let athlete = practice.athlete,
               let practiceIndex = athlete.practices.firstIndex(of: practice) {
                athlete.practices.remove(at: practiceIndex)
                log.debug("Removed practice from athlete's array")
            }

            // Delete associated video clips
            for videoClip in practice.videoClips {
                if let athlete = videoClip.athlete,
                   let clipIndex = athlete.videoClips.firstIndex(of: videoClip) {
                    athlete.videoClips.remove(at: clipIndex)
                }
                modelContext.delete(videoClip)
                log.debug("Deleted associated video clip: \(videoClip.fileName)")
            }

            // Delete associated notes
            for note in practice.notes {
                modelContext.delete(note)
                log.debug("Deleted associated note")
            }

            modelContext.delete(practice)
            log.info("Deleted practice from context")

            do {
                try modelContext.save()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                log.info("Successfully saved practice deletion")
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                log.error("Failed to delete practice: \(error.localizedDescription)")
            }
        }
    }
    
    private func deletePracticesFromFiltered(offsets: IndexSet) {
        let idsToDelete = offsets.map { filteredPractices[$0].persistentModelID }
        let toDelete = practices.filter { idsToDelete.contains($0.persistentModelID) }
        for practice in toDelete { deleteSinglePractice(practice) }
    }
}

struct PracticeListRow: View {
    let practice: Practice
    let onDelete: () -> Void

    var body: some View {
        NavigationLink(destination: PracticeDetailView(practice: practice)) {
            PracticeRow(practice: practice)
        }
        .swipeActions {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
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
            
            Button("Add Practice", action: onAddPractice)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityLabel("Add Practice")
        }
        .padding()
    }
}

struct PracticeRow: View {
    let practice: Practice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text((practice.date ?? .distantPast).formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Label("\(practice.videoClips.count)", systemImage: "video.fill")
                        .labelStyle(.iconOnly)
                        .foregroundColor(.blue)
                    Text("\(practice.videoClips.count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
            }
            
            if !practice.notes.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .foregroundColor(.secondary)
                    Text("\(practice.notes.count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
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
                VideoRecorderView_Refactored(athlete: athlete, practice: practice)
            }
        }
        .onChange(of: showingVideoRecorder) { _, isShowing in
            // When video recorder is dismissed, also dismiss this view
            if !isShowing && createdPractice != nil {
                createdPractice = nil
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
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
            if shouldUploadVideo {
                createdPractice = practice
                showingVideoRecorder = true
            } else {
                dismiss()
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            log.error("Failed to save practice: \(error.localizedDescription)")
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
    
    private enum PracticeSheet: Identifiable {
        case recordVideo
        case addNote
        var id: String { String(describing: self) }
    }
    
    @State private var activeSheet: PracticeSheet?
    
    var videoClips: [VideoClip] {
        practice.videoClips.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
    
    var notes: [PracticeNote] {
        practice.notes.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
    
    var body: some View {
        List {
            // Practice Info Section
            Section("Practice Details") {
                HStack {
                    Text("Date")
                        .fontWeight(.semibold)
                    Spacer()
                    Text((practice.date ?? .distantPast).formatted(date: .abbreviated, time: .omitted))
                        .foregroundColor(.secondary)
                }
            }
            
            // Actions Section
            Section("Actions") {
                Button(action: { activeSheet = .recordVideo }) {
                    Label("Record Video", systemImage: "video.badge.plus")
                        .foregroundColor(.blue)
                        .accessibilityLabel("Record Video")
                }
                
                Button(action: { activeSheet = .addNote }) {
                    Label("Add Note", systemImage: "note.text.badge.plus")
                        .foregroundColor(.green)
                        .accessibilityLabel("Add Note")
                }
                
                Button(action: {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    showingDeleteConfirmation = true
                }) {
                    Label("Delete Practice", systemImage: "trash")
                        .foregroundColor(.red)
                        .accessibilityLabel("Delete Practice")
                }
            }
            
            // Videos Section
            Section("Videos (\(videoClips.count))") {
                if videoClips.isEmpty {
                    Button(action: { activeSheet = .recordVideo }) {
                        Label("Record your first video", systemImage: "video.badge.plus")
                    }
                } else {
                    ForEach(videoClips) { clip in
                        PracticeVideoClipRow(clip: clip)
                    }
                }
            }
            
            // Notes Section
            Section("Notes (\(notes.count))") {
                if notes.isEmpty {
                    Button(action: { activeSheet = .addNote }) {
                        Label("Add your first note", systemImage: "note.text.badge.plus")
                    }
                } else {
                    ForEach(notes) { note in
                        PracticeNoteRow(note: note)
                            .swipeActions {
                                Button(role: .destructive) { delete(note: note) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete(perform: deleteNotes)
                }
            }
        }
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Removed the custom back/home button toolbar item as per instructions
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .recordVideo:
                VideoRecorderView_Refactored(athlete: practice.athlete, practice: practice)
            case .addNote:
                AddPracticeNoteView(practice: practice)
            }
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
    
    private func delete(note: PracticeNote) {
        modelContext.delete(note)
        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            log.error("Failed to delete note: \(error.localizedDescription)")
        }
    }
    
    private func deletePractice() {
        // Remove from athlete's practices array
        if let athlete = practice.athlete,
           let practiceIndex = athlete.practices.firstIndex(of: practice) {
            athlete.practices.remove(at: practiceIndex)
            log.debug("Removed practice from athlete's array")
        }
        
        // Delete associated video clips
        for videoClip in practice.videoClips {
            if let athlete = videoClip.athlete,
               let clipIndex = athlete.videoClips.firstIndex(of: videoClip) {
                athlete.videoClips.remove(at: clipIndex)
            }
            
            if let playResult = videoClip.playResult {
                modelContext.delete(playResult)
            }
            
            modelContext.delete(videoClip)
            log.debug("Deleted associated video clip: \(videoClip.fileName)")
        }
        
        // Delete associated notes
        for note in practice.notes {
            modelContext.delete(note)
            log.debug("Deleted associated note")
        }
        
        // Delete the practice itself
        modelContext.delete(practice)
        log.info("Deleted practice from context")
        
        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            log.info("Successfully saved practice deletion")
            // Navigate to Home tab instead of just dismissing
            navigateToHome()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            log.error("Failed to delete practice: \(error.localizedDescription)")
        }
    }
    
    private func navigateToHome() {
        // Post notification to switch to Home tab (index 0)
        NotificationCenter.default.post(name: .switchTab, object: 0)
    }
}

struct PracticeNoteRow: View {
    let note: PracticeNote
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.content)
                .font(.subheadline)
            
            if let createdAt = note.createdAt {
                Text(createdAt, formatter: DateFormatter.shortDateTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct PracticeVideoClipRow: View {
    let clip: VideoClip
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "video.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if let playResult = clip.playResult {
                        Text(playResult.type.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                if let createdAt = clip.createdAt {
                    Text(createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
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
    
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    PracticesView(athlete: nil)
}
