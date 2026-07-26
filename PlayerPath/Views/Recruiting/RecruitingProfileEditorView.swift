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
    // Surfaces view counts one level up from RecruitingPublishView, where the
    // full activity tiles live. Single getDocument, silent-fail.
    @State private var status: RecruitingPublishStatus?
    /// Publishable highlights that aren't on the live page yet.
    ///
    /// Stored rather than computed in `body`: the count reads
    /// `athlete.recruiting`, which decodes a JSON blob, and the clip list — doing
    /// that per render is the same trap already logged against
    /// RecruitingGolfStatBand. Refreshed wherever `status` is.
    @State private var staleHighlightCount = 0
    /// The athlete `working` was seeded from.
    ///
    /// @State, NOT a `let`: SwiftUI rebuilds this struct with whatever `athlete`
    /// the parent hands it on every re-render, so a stored property would silently
    /// track the new athlete while `working` still held the old one's bio. Only
    /// @State survives a re-render, which is exactly what makes it a witness.
    ///
    /// On a multi-athlete account the parent's `athlete` really can change under a
    /// pushed editor — PPAthleteSwitcher (Journal/Games/Stats/Videos) posts
    /// `.switchAthlete` while the More stack stays put. Every route in should carry
    /// `.id(athlete.id)` so the view is recreated instead; this is the backstop for
    /// the one that doesn't, because the failure mode is writing one athlete's bio,
    /// city and contact info onto another — and from there onto their public page.
    @State private var seededAthleteID: UUID

    init(athlete: Athlete) {
        self.athlete = athlete
        _working = State(initialValue: athlete.recruiting)
        _seededAthleteID = State(initialValue: athlete.id)
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
                // Both rows are held while a headshot is still uploading:
                // `headshotCloudURL` is written only when the upload returns, so
                // publishing inside that window ships a page with the placeholder
                // avatar and a nil og:image — and the editor shows the headshot
                // seconds later, so nothing ever tells the athlete their live page
                // is missing it.
                .disabled(isUploadingHeadshot)
                // Persist before pushing rather than relying on this view's
                // .onDisappear firing first — the publish snapshot reads the
                // saved blob, so an unsaved edit would publish stale bio text.
                Button {
                    persistIfChanged()
                    showingPublish = true
                } label: {
                    Label("Share Profile", systemImage: "square.and.arrow.up")
                }
                .disabled(isUploadingHeadshot)
                // Pro-gated to match the publish screen's Profile Activity section:
                // a lapsed subscription leaves isPublished true while the CF serves
                // a dark page, so live-looking view counts there would be a lie.
                if isPro, let status, status.isPublished {
                    Label {
                        Text("\(status.viewCount) total view\(status.viewCount == 1 ? "" : "s") · \(status.viewsThisWeek) this week")
                    } icon: {
                        Image(systemName: "eye.fill")
                    }
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
                    // "Live since", NOT "last updated": publish carries publishedAt
                    // forward from the first publish, so wording it as a freshness
                    // date would tell someone who republished yesterday that their
                    // page is months old.
                    if let publishedAt = status.publishedAt {
                        Label {
                            Text("Live since \(DateFormatter.mediumDate.string(from: publishedAt))")
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                    }
                }
                if staleHighlightCount > 0 {
                    staleHighlightsRow
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
        .task {
            status = try? await RecruitingProfileService.shared.fetchStatus(athleteId: athlete.id)
            refreshStaleHighlightCount()
        }
        .onChange(of: showingPublish) { _, isShowing in
            // Publish/unpublish happens on the pushed screen — refresh on return.
            guard !isShowing else { return }
            // Snapshot before the unstructured Task: reading a @Model property
            // on an invalidated model traps.
            let athleteId = athlete.id
            Task {
                status = try? await RecruitingProfileService.shared.fetchStatus(athleteId: athleteId)
                // Publishing is exactly what clears this nudge, so it has to be
                // recomputed on the way back — and AFTER status lands, since it
                // gates on isPublished.
                refreshStaleHighlightCount()
            }
        }
        .onAppear {
            // `.task` runs once per view identity, so a clip flagged as a
            // highlight while this screen sat in the More stack wouldn't show up
            // without this. No-op on the first appear (status is still nil).
            refreshStaleHighlightCount()
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
                    // Whose profile this is. On a multi-athlete account the way in
                    // (a More-tab row, a view-alert push tap) doesn't always make
                    // that obvious, and everything below goes on a public page.
                    Text(athlete.name)
                        .font(.headingMedium)
                        .lineLimit(1)

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
        // The Storage owner segment is resolved inside VideoCloudManager off the
        // signed-in account, matching the path publish() derives; the cached
        // firebaseAuthUid rides along only as a fallback.
        let ownerUID = athlete.user?.firebaseAuthUid
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
            // Persist immediately rather than waiting for .onDisappear: publish
            // snapshots the SAVED blob, so a publish that happens before this view
            // is dismissed would otherwise still see a nil headshot URL.
            persistIfChanged()
        } catch {
            // Prefer the thrown reason: the owner check moved into
            // VideoCloudManager, so a signed-out upload arrives here as
            // VideoCloudError rather than as its own guard, and telling someone to
            // check their connection would send them after the wrong problem.
            headshotError = (error as? LocalizedError)?.errorDescription
                ?? "Upload failed. Check your connection and try again."
            ErrorHandlerService.shared.handle(error, context: "RecruitingProfileEditorView.uploadHeadshot", showAlert: false)
        }
    }

    /// Clears the headshot and best-effort-deletes the Storage object so Remove
    /// doesn't orphan it (replace overwrites in place; only Remove leaks otherwise
    /// — nothing else reclaims `recruiting_headshots/`).
    private func removeHeadshot() {
        let ownerUID = athlete.user?.firebaseAuthUid
        let athleteId = athlete.id
        Task { try? await VideoCloudManager.shared.deleteRecruitingHeadshot(athleteId: athleteId, ownerUID: ownerUID) }
        working.headshotCloudURL = nil
    }

    /// The staleness nudge. `highlights` and `golfStats` are publish-time
    /// snapshots and the picker never self-heals — `load()` seeds the selection
    /// from the persisted curation, so newly flagged highlights stay unselected
    /// forever. Publish in February with 3 clips, flag 17 more by June, and the
    /// same link still serves February. Nothing else in the app says so: the only
    /// mention of republishing is a footer on the publish screen itself.
    private var staleHighlightsRow: some View {
        Button {
            persistIfChanged()
            showingPublish = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(staleHighlightCount == 1
                         ? "1 new highlight isn't on your page yet"
                         : "\(staleHighlightCount) new highlights aren't on your page yet")
                        .font(.bodySmall)
                        .multilineTextAlignment(.leading)
                    Text("Update to put your best film in front of coaches.")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text("Update")
                    .font(.bodySmall.weight(.semibold))
                    .foregroundStyle(ppAccent)
            }
        }
        .buttonStyle(.plain)
        .disabled(isUploadingHeadshot)
    }

    /// Recomputes the nudge count. Silent (0) unless we can say something TRUE:
    /// the page must be live, and the curation must be known — a profile published
    /// before `publishedClipIDs` was persisted has unknown page contents, and
    /// counting every highlight as "new" there would claim staleness we can't
    /// verify. The next publish heals it.
    private func refreshStaleHighlightCount() {
        guard !athlete.isDeleted, athlete.modelContext != nil,
              let status, status.isPublished,
              let published = athlete.recruiting.publishedClipIDs else {
            staleHighlightCount = 0
            return
        }
        let live = Set(published)
        staleHighlightCount = (athlete.videoClips ?? [])
            .filter { $0.isPublishableHighlight && !live.contains($0.id) }
            .count
    }

    // MARK: - Persistence

    /// Single exit path: persist + sync only when the bio actually changed.
    /// `version` is bumped later in uploadLocalAthletes, not here.
    private func persistIfChanged() {
        // Never write a snapshot back onto a DIFFERENT athlete. See seededAthleteID:
        // if these disagree the view was re-rendered with another profile while
        // holding this one's bio, and saving would publish A's PII on B's page.
        // Dropping the edit is the safe side of that trade.
        guard athlete.id == seededAthleteID else { return }

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
