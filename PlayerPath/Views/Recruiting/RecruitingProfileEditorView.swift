//
//  RecruitingProfileEditorView.swift
//  PlayerPath
//
//  Editor for an athlete's video-first recruiting profile. Edits a local copy of
//  the JSON-blob bio and persists + syncs on exit, matching EditAthleteView's
//  "apply immediately" convention.
//
//  Deliberately NOT wrapped in `.proRequired()`, and it must never be: that
//  modifier replaces the whole screen, and this screen is the ONLY route to
//  RecruitingPublishView — which holds the unpublish kill switch that a
//  lapsed-Pro family must always be able to reach. Gating here quietly defeated
//  firestore.rules, the CF, and the rules test that all deliberately allow a
//  free-tier unpublish. Pro is enforced on the publish ACTION instead; anyone can
//  fill the profile in, which is also the better funnel.
//

import SwiftUI
import SwiftData
import PhotosUI

struct RecruitingProfileEditorView: View {
    let athlete: Athlete

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent

    @State private var working: RecruitingInfo
    @State private var headshotItem: PhotosPickerItem?
    @State private var isUploadingHeadshot = false
    @State private var headshotError: String?
    @State private var showingPublish = false
    @State private var showingPaywall = false

    init(athlete: Athlete) {
        self.athlete = athlete
        _working = State(initialValue: athlete.recruiting)
    }

    private var isGolf: Bool { (athlete.sport ?? .baseball) == .golf }
    private var isPro: Bool { authManager.currentTier >= .pro }

    var body: some View {
        Form {
            if !isPro { upsellSection }
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
                    // Curated IDs, so the preview shows the clips actually on the
                    // published page rather than the newest 8.
                    RecruitingProfileView(athlete: athlete, info: working,
                                          curatedClipIDs: working.publishedClipIDs)
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
        .sheet(isPresented: $showingPaywall) {
            if let user = authManager.localUser {
                ImprovedPaywallView(user: user, requiredTier: .pro)
            }
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

    /// Upsell for non-Pro accounts. A card rather than a screen-replacing gate:
    /// everything here still works, and only publishing needs Pro. Mirrors the
    /// locked-tile shape in GolfStrokesGainedSection.
    private var upsellSection: some View {
        Section {
            Button {
                Haptics.light()
                showingPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.title3)
                        .foregroundColor(ppAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Publishing is a Pro feature")
                            .font(.headingMedium)
                            .foregroundColor(.primary)
                        Text("Build your profile now — you'll need Pro to put it online as a link for college coaches.")
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

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
            RecruitingTextField("City", prompt: "Austin", text: $working.city.orEmpty())
            RecruitingTextField("State", prompt: "TX", text: $working.state.orEmpty(),
                                autocapitalization: .characters, autocorrect: false)
            RecruitingTextField("High school", prompt: "Austin High",
                                text: $working.highSchool.orEmpty())
            RecruitingTextField("Club team", prompt: "Texas Thunder 16U",
                                text: $working.clubTeam.orEmpty())
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
        // publishConsentAt and publishedClipIDs on publish; without carrying them
        // forward, this autosave would erase them on the way out — re-showing the
        // guardian gate to someone who already consented, and losing the curated
        // clip order so the next publish silently reverts to newest-8.
        // Any new field written by a pushed screen needs a line here.
        var working = self.working
        let saved = athlete.recruiting
        working.publishConsentAt = saved.publishConsentAt ?? working.publishConsentAt
        working.publishedClipIDs = saved.publishedClipIDs ?? working.publishedClipIDs

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
