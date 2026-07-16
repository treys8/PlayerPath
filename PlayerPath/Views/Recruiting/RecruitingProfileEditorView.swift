//
//  RecruitingProfileEditorView.swift
//  PlayerPath
//
//  Pro-gated editor for an athlete's video-first recruiting profile (Phase 1:
//  in-app only — nothing is published). Edits a local copy of the JSON-blob bio
//  and persists + syncs on exit, matching EditAthleteView's "apply immediately"
//  convention.
//

import SwiftUI
import SwiftData
import PhotosUI

struct RecruitingProfileEditorView: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent

    @State private var working: RecruitingInfo
    @State private var headshotItem: PhotosPickerItem?
    @State private var isUploadingHeadshot = false
    @State private var headshotError: String?
    @State private var showingPublish = false

    init(athlete: Athlete) {
        self.athlete = athlete
        _working = State(initialValue: athlete.recruiting)
    }

    private var isGolf: Bool { (athlete.sport ?? .baseball) == .golf }

    var body: some View {
        Form {
            headshotSection
            basicsSection
            aboutSection

            if isGolf {
                Section {
                    Label("Your scoring stats (handicap, averages, GIR) appear on your profile automatically.",
                          systemImage: "figure.golf")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                }
            } else {
                RecruitingBaseballSection(info: $working)
            }

            RecruitingPIISection(info: $working)

            Section {
                NavigationLink {
                    RecruitingProfileView(athlete: athlete, info: working)
                } label: {
                    Label("Preview Profile", systemImage: "eye")
                }
                // Persist before pushing rather than relying on this view's
                // .onDisappear firing first — the publish snapshot reads the
                // saved blob, so an unsaved edit would publish stale bio text.
                Button {
                    persistIfChanged()
                    showingPublish = true
                } label: {
                    Label("Share Profile", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("This is what a college coach will see. Your changes save automatically.")
            }
        }
        .tint(ppAccent)
        .navigationTitle("Recruiting Profile")
        .navigationBarTitleDisplayMode(.inline)
        .ppAccent(for: athlete.sport)
        .navigationDestination(isPresented: $showingPublish) {
            RecruitingPublishView(athlete: athlete)
        }
        .onChange(of: headshotItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadHeadshot(newItem) }
        }
        .onAppear {
            AnalyticsService.shared.trackScreenView(
                screenName: "Recruiting Profile Editor",
                screenClass: "RecruitingProfileEditorView"
            )
        }
        .onDisappear(perform: persistIfChanged)
    }

    // MARK: - Sections

    private var headshotSection: some View {
        Section {
            HStack(spacing: 16) {
                RecruitingHeadshotImage(url: working.headshotCloudURL, size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    PhotosPicker(selection: $headshotItem, matching: .images) {
                        Label(working.headshotCloudURL == nil ? "Add Headshot" : "Change Headshot",
                              systemImage: "camera")
                    }
                    .disabled(isUploadingHeadshot)

                    if isUploadingHeadshot {
                        ProgressView().controlSize(.small)
                    } else if working.headshotCloudURL != nil {
                        Button(role: .destructive, action: removeHeadshot) {
                            Text("Remove").font(.bodySmall)
                        }
                    }
                }
                Spacer()
            }
        } header: {
            Text("Headshot")
        } footer: {
            if let headshotError {
                Text(headshotError).foregroundColor(.red)
            }
        }
    }

    private var basicsSection: some View {
        Section("Basics") {
            Picker("Grad Year", selection: $working.gradYear) {
                Text("—").tag(Int?.none)
                ForEach(gradYearOptions, id: \.self) { year in
                    Text(String(year)).tag(Int?.some(year))
                }
            }
            Picker("Height", selection: $working.heightInches) {
                Text("—").tag(Int?.none)
                ForEach(48...84, id: \.self) { inches in
                    Text("\(inches / 12)'\(inches % 12)\"").tag(Int?.some(inches))
                }
            }
            RecruitingNumberField("Weight", unit: "lbs", value: weightBinding, isInteger: true)
            TextField("City", text: $working.city.orEmpty())
            TextField("State", text: $working.state.orEmpty())
            TextField("High school", text: $working.highSchool.orEmpty())
            TextField("Club / travel team", text: $working.clubTeam.orEmpty())
        }
    }

    private var aboutSection: some View {
        Section("About") {
            TextField("Short bio — what should a coach know?",
                      text: $working.bio.orEmpty(), axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Bindings / data

    /// Grad-year choices: this year through +6, plus any already-saved year that
    /// falls outside that window (so editing an older profile can't drop it).
    private var gradYearOptions: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        var years = Array((currentYear - 1)...(currentYear + 6))
        if let saved = working.gradYear, !years.contains(saved) {
            years.insert(saved, at: 0)
        }
        return years
    }

    /// Bridges the Int? weight model field to the Double?-based number field.
    private var weightBinding: Binding<Double?> {
        Binding(
            get: { working.weightLbs.map(Double.init) },
            set: { working.weightLbs = $0.map { Int($0.rounded()) } }
        )
    }

    // MARK: - Headshot upload

    @MainActor
    private func uploadHeadshot(_ item: PhotosPickerItem) async {
        // Snapshot model attributes BEFORE any await — a concurrent delete that
        // invalidates the @Model mid-await would trap on a later property read.
        guard let ownerUID = athlete.user?.firebaseAuthUid else {
            headshotError = "Sign in required to upload a headshot."
            return
        }
        let athleteId = athlete.id
        isUploadingHeadshot = true
        headshotError = nil
        defer { isUploadingHeadshot = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                headshotError = "Couldn't read that image. Try another."
                return
            }
            // Decode + downscale + JPEG-encode off the main actor — a full-res
            // library photo would otherwise freeze the Form for the whole redraw.
            // Data in / Data out, so no @Model crosses the isolation boundary.
            guard let jpeg = await Task.detached(priority: .userInitiated, operation: {
                UIImage(data: data)?.recruitingHeadshotData()
            }).value else {
                headshotError = "Couldn't read that image. Try another."
                return
            }
            let url = try await VideoCloudManager.shared.uploadRecruitingHeadshot(
                imageData: jpeg, athleteId: athleteId, ownerUID: ownerUID
            )
            working.headshotCloudURL = url
        } catch {
            headshotError = "Upload failed. Check your connection and try again."
            ErrorHandlerService.shared.handle(error, context: "RecruitingProfileEditorView.uploadHeadshot", showAlert: false)
        }
    }

    /// Clears the headshot and best-effort-deletes the Storage object so Remove
    /// doesn't orphan it (replace overwrites in place; only Remove leaks otherwise
    /// — nothing else reclaims `recruiting_headshots/`).
    private func removeHeadshot() {
        if let ownerUID = athlete.user?.firebaseAuthUid {
            let athleteId = athlete.id
            Task { try? await VideoCloudManager.shared.deleteRecruitingHeadshot(athleteId: athleteId, ownerUID: ownerUID) }
        }
        working.headshotCloudURL = nil
    }

    // MARK: - Persistence

    /// Single exit path: persist + sync only when the bio actually changed.
    /// `version` is bumped later in uploadLocalAthletes, not here.
    private func persistIfChanged() {
        // `working` was snapshotted in init, so it can't know about fields written
        // by screens pushed from here. RecruitingPublishView stamps
        // publishConsentAt on first publish; without carrying it forward, this
        // autosave would erase it on the way out and re-show the guardian gate to
        // someone who already consented.
        var working = self.working
        working.publishConsentAt = athlete.recruiting.publishConsentAt ?? working.publishConsentAt

        guard working != athlete.recruiting else { return }
        let isFirstSave = !athlete.hasRecruitingProfile
        athlete.recruiting = working   // sets needsSync = true
        ErrorHandlerService.shared.saveContext(modelContext, caller: "RecruitingProfileEditorView.onDisappear")
        AnalyticsService.shared.trackRecruitingProfileSaved(
            athleteID: athlete.id.uuidString,
            sport: (athlete.sport ?? .baseball).rawValue,
            isFirstSave: isFirstSave,
            hasHeadshot: working.headshotCloudURL != nil,
            fieldsCompleted: working.filledFieldCount
        )
        if let user = athlete.user {
            Task { try? await SyncCoordinator.shared.syncAthletes(for: user) }
        }
    }
}
