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
    @Environment(\.scenePhase) private var scenePhase

    @State private var working: RecruitingInfo
    @State private var headshotItem: PhotosPickerItem?
    @State private var isUploadingHeadshot = false
    @State private var headshotError: String?
    @State private var showingPublish = false
    @State private var showingPaywall = false
    // Surfaces view counts one level up from RecruitingPublishView, where the
    // full activity tiles live. Single getDocument, silent-fail.
    @State private var status: RecruitingPublishStatus?
    /// True once a status read has SUCCEEDED (a nil status then really means "no
    /// page"). Until then the status card stays hidden — a failed read must never
    /// render as "Not published yet" over a page that's live.
    @State private var statusKnown = false
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
        // Normalized at SEED as well as on the picker (gradYearBinding), because the
        // two cover different populations and the seed one is the bigger: an athlete
        // whose grad year was ALREADY under-13 — set on another device, or before this
        // shipped — never passes through the picker's setter, so its contact opt-ins
        // would render ON-and-disabled indefinitely. That is the armed-switch state
        // the `include*` flags exist to rule out, and at launch it is the majority of
        // affected profiles.
        //
        // The published page is safe either way (`visibleContactItems` plus the Cloud
        // Function's `contactSection`); this is about the editor never showing a
        // state that isn't true. `persistIfChanged`'s `working != athlete.recruiting`
        // check sees the difference, so it persists on the way out — deliberately
        // dirtying those profiles once.
        var seeded = athlete.recruiting
        if seeded.gradYearImpliesUnder13 {
            seeded.includeGPA = false
            seeded.includeContactEmail = false
            seeded.includeContactPhone = false
        }
        // Collapses free-text states typed before the picker existed ("MISSISSIPPI",
        // "ms") to the code the picker tags, so they select the right row instead of
        // showing as an unknown extra. Same dirty-once-on-exit trade as above.
        seeded.state = USState.normalized(seeded.state)
        _working = State(initialValue: seeded)
        _seededAthleteID = State(initialValue: athlete.id)
    }

    private var isGolf: Bool { (athlete.sport ?? .baseball) == .golf }
    private var isPro: Bool { authManager.currentTier >= .pro }
    private var isPublished: Bool { status?.isPublished == true }

    /// Edits here that the live page doesn't show yet. Computed off `working` (in
    /// memory, no blob decode) against the doc `status` fetched.
    private var hasUnpublishedChanges: Bool {
        guard isPublished, isPro, let status else { return false }
        return RecruitingProfileService.hasUnpublishedChanges(
            published: status.publishedFields, info: working,
            name: athlete.name, sport: athlete.sport ?? .baseball
        )
    }

    var body: some View {
        Form {
            // Not for a lapsed PUBLISHED page — "you'll need Pro to put it online"
            // is wrong there, and the status card below says what actually
            // happened (offline, renew).
            if !isPro && !isPublished { upsellSection }
            if statusKnown {
                RecruitingStatusCard(
                    status: status,
                    isPro: isPro,
                    hasUnpublishedChanges: hasUnpublishedChanges,
                    staleHighlightCount: staleHighlightCount,
                    liveSinceText: status?.publishedAt.map {
                        liveSinceText(publishedAt: $0, updatedAt: status?.updatedAt)
                    },
                    isBusy: isUploadingHeadshot,
                    onOpenShare: openShare,
                    onRenew: { showingPaywall = true }
                )
            }
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
                    // published page rather than the newest 8 — or, if the athlete
                    // re-picked clips on Share Profile this session without
                    // publishing, those picks.
                    RecruitingProfileView(athlete: athlete, info: working,
                                          curatedClipIDs: RecruitingProfileService.shared.draftSelection(for: athlete.id)
                                              ?? working.publishedClipIDs)
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
                // View counts, live-since and the out-of-date nudges moved to the
                // status card at the top — see RecruitingStatusCard.
                Button(action: openShare) {
                    // "Share" promises a link that doesn't exist yet on a profile
                    // that has never been published.
                    Label(isPublished ? "Share Profile" : "Publish Profile",
                          systemImage: isPublished ? "square.and.arrow.up" : "paperplane")
                }
                .disabled(isUploadingHeadshot)
            } footer: {
                // Was "Your changes save automatically", which read as though the
                // public page updated too. It only changes on Update.
                Text("Preview shows what a college coach will see. Changes save in the app — your public page updates when you tap Update on Share Profile.")
            }
        }
        .tint(ppAccent)
        .navigationTitle("Recruiting Profile")
        .navigationBarTitleDisplayMode(.inline)
        // Hidden across editor, Preview and Share so pushes between them don't
        // flicker the bar in and out; at rest it covered the bio field.
        .toolbar(.hidden, for: .tabBar)
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
            await refreshStatus(athleteId: athlete.id)
            refreshStaleHighlightCount()
        }
        .onChange(of: showingPublish) { _, isShowing in
            // Publish/unpublish happens on the pushed screen — refresh on return.
            guard !isShowing else { return }
            // "Delete Profile Data" on the publish screen CLEARS headshotCloudURL
            // (the Storage object is gone, so the stored download URL 404s). Our
            // `working` snapshot predates that, so without re-seeding it here
            // `.onDisappear`'s persistIfChanged writes the stale URL straight back
            // — resurrecting a pointer to an object that no longer exists, showing
            // a broken headshot in this editor, and making the next publish stamp a
            // dead `headshotPath` onto the public page. Unconditionally safe:
            // persistIfChanged runs immediately before the push, so these two agree
            // on every field the publish screen didn't deliberately change.
            //
            // NOT foldable into persistIfChanged's carry-forward block — that block
            // is "saved wins if non-nil", and this is a deliberate nil-CLEAR, which
            // that rule would silently discard. It's also why the editor's own
            // Remove button can't use the same mechanism.
            //
            // `publishedClipIDs` rides along because the Preview Profile row above
            // renders `working.publishedClipIDs`: a publish that reordered or
            // changed the clip set writes the new list to the model, and without
            // this the in-session preview goes on showing the OLD hero and order
            // (or the newest-8 fallback) while the live page has the new one.
            // persistIfChanged's carry-forward can't help — it operates on a local
            // copy, so `self.working` is never healed.
            //
            // publishConsentAt / publishedContactKinds are deliberately NOT copied
            // here: nothing in this editor renders them, and persistIfChanged
            // already carries them forward on save. A second mechanism for the same
            // field is exactly how those two blocks would drift apart.
            if !athlete.isDeleted, athlete.modelContext != nil {
                // One blob decode, not two — `recruiting` is a JSON blob.
                let saved = athlete.recruiting
                working.headshotCloudURL = saved.headshotCloudURL
                working.publishedClipIDs = saved.publishedClipIDs
            }
            // Snapshot before the unstructured Task: reading a @Model property
            // on an invalidated model traps.
            let athleteId = athlete.id
            Task {
                await refreshStatus(athleteId: athleteId)
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
        // Backgrounding doesn't fire .onDisappear, so a bio typed here and then
        // left while iOS terminates the app in the background was simply lost —
        // despite the footer's "saves automatically". Guarded like the
        // showingPublish handler: persistIfChanged reads athlete.id first, and a
        // deleted @Model traps on any property read.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, !athlete.isDeleted, athlete.modelContext != nil else { return }
            persistIfChanged()
        }
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
                    // Carries the sport for a dual-sport person: those are two
                    // profiles with the same name and two separate public pages,
                    // so the name alone doesn't say which one this is.
                    Text(athlete.nameWithSportIfShared)
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
        Section {
            Picker("Grad Year", selection: gradYearBinding) {
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
            RecruitingNumberField("Weight", unit: "lbs", value: weightBinding, isInteger: true,
                                  validRange: RecruitingInputRange.weight)
            RecruitingTextField("City", prompt: "Austin", text: $working.city.orEmpty())
            RecruitingStatePicker(state: $working.state)
            RecruitingTextField("High School", prompt: "Austin High",
                                text: $working.highSchool.orEmpty())
            RecruitingTextField("Club Team", prompt: "Texas Thunder 16U",
                                text: $working.clubTeam.orEmpty())
        } header: {
            Text("Basics")
        } footer: {
            if RecruitingInputRange.isFlagged(working.weightLbs.map(Double.init), RecruitingInputRange.weight) {
                Text(RecruitingInputRange.flaggedNote)
            }
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

    /// Grad year, plus the contact opt-ins it gates.
    ///
    /// Picking a year that implies the athlete is under 13 forces the GPA, email and
    /// phone toggles off (see `RecruitingInfo.gradYearImpliesUnder13`). Done on the
    /// WRITE rather than in an `.onChange` inside `RecruitingPIISection`: that's a
    /// different section of this Form, and its modifiers aren't guaranteed to be
    /// active in a lazily materialised List while the athlete is up here in Basics.
    ///
    /// The published page is safe either way — `visibleContactItems` withholds those
    /// fields, and `contactSection` in the Cloud Function withholds them again at
    /// render time. This exists so the editor never shows an armed toggle that
    /// silently does nothing, which was the whole complaint the `include*` flags were
    /// added to answer.
    private var gradYearBinding: Binding<Int?> {
        Binding(
            get: { working.gradYear },
            set: { newValue in
                working.gradYear = newValue
                guard working.gradYearImpliesUnder13 else { return }
                working.includeGPA = false
                working.includeContactEmail = false
                working.includeContactPhone = false
            }
        )
    }

    /// Grad-year choices: last year through +6 (last year keeps post-grad and
    /// JUCO-transfer athletes selectable), plus any already-saved year that
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

    /// "Live since Feb 3, 2026", plus "· updated Jul 26, 2026" once a republish has
    /// actually moved the page on.
    ///
    /// Both dates, because neither answers the question alone. `publishedAt` is
    /// carried forward from the FIRST publish and never moves, so on its own it
    /// tells someone who republished this morning that their page is months old.
    /// `updatedAt` on its own loses how long the link has been in circulation,
    /// which is the other half of what an athlete opens this row to check.
    ///
    /// The updated half is suppressed on the same calendar day so a fresh first
    /// publish doesn't read "Live since today · updated today". Both use the full
    /// date rather than the shorter month/day: a page updated two seasons after it
    /// went live is exactly the case this line exists for, and a bare "Jul 26"
    /// would be silent about which year — the same year-ambiguity that made the
    /// published page's clip captions unreadable (P4.2).
    private func liveSinceText(publishedAt: Date, updatedAt: Date?) -> String {
        let base = "Live since \(DateFormatter.mediumDate.string(from: publishedAt))"
        guard let updatedAt,
              !Calendar.current.isDate(updatedAt, inSameDayAs: publishedAt)
        else { return base }
        return base + " · updated \(DateFormatter.mediumDate.string(from: updatedAt))"
    }

    /// Persist before pushing rather than relying on this view's .onDisappear
    /// firing first — the publish snapshot reads the saved blob, so an unsaved
    /// edit would publish stale bio text.
    private func openShare() {
        persistIfChanged()
        showingPublish = true
    }

    /// Re-reads publish state, keeping what we have when the read FAILS — the same
    /// rule as RecruitingPublishView.refreshStatus. `try?` flattened a failure
    /// into nil, i.e. "no page", which the status card would render as "Not
    /// published yet" over a page that's live.
    private func refreshStatus(athleteId: UUID) async {
        do {
            status = try await RecruitingProfileService.shared.fetchStatus(athleteId: athleteId)
            statusKnown = true
        } catch {
            ErrorHandlerService.shared.handle(error, context: "RecruitingProfileEditorView.refreshStatus",
                                              showAlert: false)
        }
    }

    /// The staleness nudge's count. `highlights` and `golfStats` are publish-time
    /// snapshots and the picker never self-heals — `load()` seeds the selection
    /// from the persisted curation, so newly flagged highlights stay unselected
    /// forever. Publish in February with 3 clips, flag 17 more by June, and the
    /// same link still serves February. Shown in RecruitingStatusCard.
    ///
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
        staleHighlightCount = athlete.recruitingHighlights
            .filter { $0.hasPublishableUpload && !live.contains($0.id) }
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
        // Without this the autosave erases the re-consent baseline on the way out,
        // which reads as "unknown" and disarms the gate — so the very next
        // republish would newly expose a phone number with no re-prompt.
        working.publishedContactKinds = saved.publishedContactKinds ?? working.publishedContactKinds

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
