//
//  RecruitingPublishView.swift
//  PlayerPath
//
//  The share surface: turns a recruiting profile into a public link a college
//  coach can open in any browser, and takes it back down.
//
//  Deliberately NOT wrapped in `.proRequired()`. That modifier replaces the whole
//  screen, which would lock a lapsed-Pro family out of the unpublish button and
//  leave their kid's page live with no way to pull it. Instead only the publish
//  action is tier-gated — mirroring firestore.rules, which allows
//  `isPublished == false` at any tier for exactly this reason.
//
//  The same applies to every screen on the ROUTE here. RecruitingProfileEditorView
//  is the only way in, and while it carried `.proRequired()` the kill switch was
//  unreachable the moment Pro lapsed — with rules, the Cloud Function, and the
//  "lapsed owner CAN unpublish" rules test all still passing. Don't gate the path.
//

import SwiftUI
import SwiftData

struct RecruitingPublishView: View {
    let athlete: Athlete

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent
    /// Pops back to the editor for "Fill These In". Safe as a pop rather than a
    /// push: RecruitingProfileEditorView is this screen's ONLY route in, so there
    /// is no stack where dismissing lands somewhere other than the fields the
    /// readiness checklist is talking about.
    @Environment(\.dismiss) private var dismiss

    @State private var status: RecruitingPublishStatus?
    @State private var selection: [UUID] = []
    @State private var isLoading = true
    /// True when the last status read THREW. Distinguishes "couldn't check" from
    /// `fetchStatus`'s legitimate nil-for-no-profile, which look identical in
    /// `status` alone.
    @State private var statusLoadFailed = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var consentAcknowledged = false
    @State private var showingUnpublishConfirm = false
    @State private var showingResetConfirm = false
    @State private var showingDeleteDataConfirm = false
    /// Pre-publish checklist rows.
    ///
    /// @State rather than computed in `body`: the items read `athlete.recruiting`,
    /// which decodes a JSON blob, and doing that on every render is the trap
    /// already logged against RecruitingGolfStatBand and the editor's stale-clip
    /// count. Recomputed in `load()`, which is enough — these fields are only
    /// editable one screen back, and this view is recreated on the way in.
    @State private var readiness: [RecruitingReadinessItem] = []
    @State private var showingPaywall = false
    @State private var showingQR = false
    /// (completed, total) while publish makes the web-safe copy of each clip.
    /// That step downloads, transcodes and uploads, so it can run tens of seconds
    /// on a first publish — long enough that a bare spinner reads as a hang.
    @State private var renditionStep = 0
    @State private var renditionTotal = 0
    /// Non-nil right after a successful publish — drives the success sheet.
    /// Carries the URL + skipped-clip count so the sheet needs no re-fetch.
    @State private var publishSuccess: PublishSuccess?
    /// Success that landed while the paywall sheet was still up (a fast publish
    /// resumed from onPurchaseCompleted can beat the dismiss animation).
    /// Presenting over a live sibling sheet gets silently dropped by SwiftUI —
    /// and the binding would then stay "presented", blocking every later sheet
    /// from this view. Parked here and promoted once the paywall is gone.
    @State private var pendingSuccess: PublishSuccess?
    /// The error-path twin of `pendingSuccess`. A publish resumed from the paywall
    /// most often fails on the tier race — i.e. exactly while that sheet is still
    /// dismissing — and an alert raised then is silently dropped, leaving a paying
    /// customer with no page and no explanation at all.
    @State private var pendingError: String?
    /// The athlete `selection` was loaded for. Same witness as the editor's — see
    /// RecruitingProfileEditorView.seededAthleteID for why it must be @State and
    /// what goes wrong without it. Here the stake is publishing one athlete's
    /// curated clips and consent stamp against another athlete's profile doc.
    @State private var seededAthleteID: UUID

    init(athlete: Athlete) {
        self.athlete = athlete
        _seededAthleteID = State(initialValue: athlete.id)
    }

    /// Identifiable so the success sheet uses `.sheet(item:)` — with an
    /// isPresented binding over an optional, dismissal nils the value while the
    /// content closure is still on screen, flashing a blank sheet.
    struct PublishSuccess: Identifiable {
        let id = UUID()
        let url: URL
        let skipped: Int
    }

    private var isPro: Bool { authManager.currentTier >= .pro }
    private var isPublished: Bool { status?.isPublished == true }
    private var needsConsent: Bool { athlete.recruiting.publishConsentAt == nil }
    /// Tier is deliberately NOT part of this. Disabling the button at free tier
    /// hides the upgrade path behind a dead control; the app's convention (see
    /// GameDetailView.generateReelTapped) is to keep the action live and let the
    /// tap open the paywall — the tap IS the conversion moment.
    private var canPublish: Bool {
        !selection.isEmpty && !isWorking && (!needsConsent || consentAcknowledged)
    }

    var body: some View {
        Form {
            if isLoading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else {
                // A failed read must not let the rest of the screen assert "no page
                // exists" — but it must not hide the curation and publish path
                // either, or a first-time athlete offline is left with nothing to
                // do. The sections that depend on KNOWING the live state
                // (live link, activity, unpublish, reset) are already keyed on a
                // non-nil `status`, so they stay hidden on their own.
                if status == nil && statusLoadFailed { statusUnavailableSection }
                if isPublished, let url = status?.shareURL {
                    liveLinkSection(url: url)
                    // Stats about a dark page would read as "coaches can still
                    // see this" — only a live (Pro) page shows its numbers.
                    if isPro { activitySection }
                }
                clipsSection
                // Only while something is unmet — see RecruitingReadinessSection
                // on why an all-green checklist doesn't earn its space.
                if readiness.contains(where: { !$0.isDone }) {
                    RecruitingReadinessSection(items: readiness, isBusy: isWorking) { dismiss() }
                }
                if needsConsent { consentSection }
                // Shown when published too: a lapsed-Pro account would otherwise
                // face a disabled "Update" button with no explanation of why.
                if !isPro { upgradeSection }
                publishSection
                if isPublished { unpublishSection }
                // Reset needs only a profile doc, not a live page: an unpublished
                // profile still holds its token, and the next publish would
                // resurrect the old link. Pro-only (mirrors the rules) — a
                // lapsed account's remedy is Unpublish, which darkens the page
                // for everyone anyway.
                if status != nil && isPro { resetLinkSection }
                // Last, because it's the most destructive thing here. Needs a doc
                // to delete, but NOT Pro — see deleteDataSection.
                if status != nil { deleteDataSection }
            }
        }
        .navigationTitle("Share Profile")
        .navigationBarTitleDisplayMode(.inline)
        .listSectionSpacing(.compact)
        .tint(ppAccent)
        .ppAccent(for: athlete.sport)
        .task { await load() }
        // View counts otherwise only move on a fresh push of this screen, which
        // is the wrong affordance for the number an athlete comes back to check.
        .refreshable { await load(showSpinner: false) }
        .onAppear {
            // `.task` runs once per view identity, so a field filled in via
            // "Fill These In" wouldn't tick over on the way back without this —
            // the exact trap already logged against the editor's stale-clip count,
            // and here it would land on the one control whose whole job is to send
            // the athlete off to fix something and welcome them back.
            refreshReadiness()
            AnalyticsService.shared.trackScreenView(
                screenName: "Recruiting Publish",
                screenClass: "RecruitingPublishView"
            )
        }
        .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showingQR) {
            if let url = status?.shareURL {
                // A scanned code is its own channel — the showcase-table case.
                RecruitingQRCodeView(athleteName: athlete.nameWithSportIfShared,
                                     url: RecruitingShareTools.taggedURL(url, channel: .qr))
            }
        }
        // Peak-motivation moment: the publish just landed, so the share verbs
        // (and any skipped-clip warning) come to the athlete instead of hiding
        // in the form. Replaces the old "Profile published" notice alert.
        .sheet(item: $publishSuccess) { success in
            RecruitingPublishSuccessView(athlete: athlete,
                                         url: success.url,
                                         skippedClipCount: success.skipped)
        }
        .onChange(of: showingPaywall) { _, isShowing in
            if !isShowing, let pending = pendingSuccess {
                pendingSuccess = nil
                publishSuccess = pending
            }
            if !isShowing, let pending = pendingError {
                pendingError = nil
                errorMessage = pending
            }
        }
        .sheet(isPresented: $showingPaywall) {
            if let user = authManager.localUser {
                // Resume the publish the athlete already asked for once Pro lands,
                // rather than making them find this button again.
                ImprovedPaywallView(user: user, requiredTier: .pro) {
                    Task { await publish() }
                }
            }
        }
    }

    // MARK: - Sections

    private func liveLinkSection(url: URL) -> some View {
        Section {
            RecruitingShareCard(
                url: url,
                // Sport-qualified for a dual-sport person: this card names the
                // profile a live link belongs to, and both of that person's
                // profiles have the same name and different links.
                athleteName: athlete.nameWithSportIfShared,
                isPro: isPro,
                sport: athlete.sport,
                onShowQR: { showingQR = true },
                onEmail: coachEmailURL(url: url).map { emailURL in
                    {
                        // No mail app configured → open() fails with no UI at
                        // all. Falling back to the pasteboard beats a button
                        // that does nothing.
                        UIApplication.shared.open(emailURL, options: [:]) { opened in
                            if !opened {
                                // Still the mail channel: that was the intent, and
                                // the athlete pastes this into a mail app.
                                UIPasteboard.general.string =
                                    RecruitingShareTools.taggedURL(url, channel: .mail).absoluteString
                                errorMessage = "No mail app is set up on this device — your profile link was copied instead."
                            }
                        }
                    }
                }
            )
        }
    }

    /// Total / this-week / last-viewed. The counts come off the profile doc
    /// (written by serveRecruitingProfile, digested by recruitingViewDigest);
    /// link unfurlers and bots are already excluded server-side.
    private var activitySection: some View {
        Section("Profile Activity") {
            if let status {
                RecruitingActivityTiles(
                    totalViews: status.viewCount,
                    viewsThisWeek: status.viewsThisWeek,
                    lastViewedAt: status.lastViewedAt
                )
            }
        }
    }

    private var clipsSection: some View {
        Section {
            NavigationLink {
                RecruitingHighlightPicker(athlete: athlete, selection: $selection)
            } label: {
                HStack {
                    Label("Highlight Clips", systemImage: "film.stack")
                    Spacer()
                    Text("\(selection.count)")
                        .foregroundStyle(.secondary)
                }
            }
            // Previews the LIVE selection, not the athlete's newest highlights —
            // this is the only preview that can honestly claim to be the page.
            NavigationLink {
                RecruitingProfileView(athlete: athlete,
                                      info: athlete.recruiting,
                                      curatedClipIDs: selection)
            } label: {
                Label("Preview Profile", systemImage: "eye")
            }
        } footer: {
            if selection.isEmpty {
                Text(hasPublishableClips
                     ? "Pick up to \(RecruitingProfileService.maxHighlights) clips. Your film is the whole point of the page — a profile without it won't get watched."
                     : "Your highlights are still uploading. This usually finishes on Wi-Fi.")
            } else {
                Text("Your best clip goes first — it's the big player at the top of the page.")
            }
        }
    }

    private var consentSection: some View {
        Section {
            Toggle(isOn: $consentAcknowledged) {
                Text("I'm this athlete's parent or guardian, or I'm 13 or older.")
                    .font(.bodyMedium)
            }
        } header: {
            Text("Before you publish")
        } footer: {
            Text("Publishing puts this profile — including the headshot and anything you chose to share — on a public web page that anyone with the link can open. You can take it down at any time.")
        }
    }

    /// Shown ABOVE the rest of the screen when we could not determine whether a
    /// page is live. Without it the remaining sections silently assert
    /// "never published" — hiding the live URL, the counts, Unpublish and Reset
    /// Link on a page that is up and being served.
    private var statusUnavailableSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Couldn't check whether this profile is live.", systemImage: "exclamationmark.triangle.fill")
                    .font(.bodySmall)
                    .foregroundStyle(Theme.warning)
                // Without this line the button below ("Publish Profile") implies no
                // page exists — the exact false assertion this section fixes.
                Text("Your link and settings are safe — this device just couldn't reach the server. Publishing will update your existing page if you already have one.")
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Haptics.light()
                    Task { await load() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }

    private var upgradeSection: some View {
        Section {
            Button {
                Haptics.light()
                showingPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Theme.warning)
                    Text(isPublished
                         ? "Your profile is offline because Pro ended. Renew to bring it back — your link doesn't change, so anything you've already sent to coaches will work again."
                         : "Publishing a public profile is a Pro feature.")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var publishSection: some View {
        Section {
            Button {
                publishTapped()
            } label: {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(isPublished ? "Update Published Profile" : "Publish Profile")
                        .font(.headingMedium)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canPublish)

            if isWorking, renditionTotal > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preparing clip \(min(renditionStep + 1, renditionTotal)) of \(renditionTotal)")
                        .font(.bodySmall)
                    ProgressView(value: Double(renditionStep), total: Double(renditionTotal))
                }
            }
        } footer: {
            if isWorking, renditionTotal > 0 {
                Text("Your clips are being converted so they play in any web browser. This happens once per clip.")
            } else if isPublished {
                Text("Republishing refreshes your stats and clips. Your link stays the same.")
            }
        }
    }

    private var unpublishSection: some View {
        Section {
            Button(role: .destructive) {
                showingUnpublishConfirm = true
            } label: {
                Text("Unpublish")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isWorking)
            .confirmationDialog("Unpublish this profile?", isPresented: $showingUnpublishConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Unpublish", role: .destructive) {
                    Task { await unpublish() }
                }
            } message: {
                Text("The link stops working immediately. Anyone who already has it will see \"profile unavailable\". You can publish again later and the same link will work.")
            }
        }
        // No footer here on purpose: the confirmation dialog above makes the
        // same "your link survives" promise at the moment it's actually needed,
        // and the publish section says it a third time. Once is enough.
    }

    /// The one action that breaks the "your link never changes" promise — on
    /// purpose. There is no per-recipient revocation on this feature (recruiters
    /// never authenticate; every share path is blind to who received it), so a
    /// leaked link's only remedies are taking the page down for everyone or
    /// minting a new link. This is the second one, and the copy doesn't soften
    /// what it costs.
    private var resetLinkSection: some View {
        Section {
            Button(role: .destructive) {
                showingResetConfirm = true
            } label: {
                Text("Reset Link")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isWorking)
            .confirmationDialog("Reset your profile link?", isPresented: $showingResetConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset Link", role: .destructive) {
                    Task { await resetLink() }
                }
            } message: {
                Text("You'll get a new link, and the current one stops working permanently — for everyone you've sent it to, including any QR codes you've shared or printed. This can't be undone.")
            }
        } footer: {
            Text("If your link ended up somewhere you didn't intend, this is how you take it back.")
        }
    }

    /// Per-profile data removal.
    ///
    /// `unpublish` only flips `isPublished`, so the doc goes on holding the
    /// athlete's name, school, bio, GPA and contact info and the headshot JPEG
    /// stays in Storage. That leftover exposure is owner-only — the Cloud Function
    /// serves nothing unless `isPublished` is true — so this is NOT a GDPR gap;
    /// account and athlete deletion already purge everything. What was missing is
    /// granularity: "delete our recruiting data" used to mean deleting the athlete
    /// and losing four seasons of film with it.
    ///
    /// **Not tier-gated**, for the same reason unpublish isn't: a lapsed-Pro
    /// family must always be able to remove their kid's data. The
    /// `recruitingTokens` claim deliberately stays behind (rules make it
    /// undeletable so a killed link can never be re-claimed) — afterwards it
    /// simply matches no profile.
    private var deleteDataSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteDataConfirm = true
            } label: {
                Text("Delete Profile Data")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isWorking)
            .confirmationDialog("Delete this profile's recruiting data?",
                                isPresented: $showingDeleteDataConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await deleteProfileData() }
                }
            } message: {
                // Names exactly what goes and what doesn't. The private copy in
                // the app is NOT deleted — claiming otherwise would be the same
                // class of wrong-copy defect as P4.8, and on a privacy promise.
                Text("Deletes the published page and everything on it, and removes the headshot image from your cloud backup. Your current link stops working permanently — publishing again creates a new one. What you typed stays in the app, and your clips, stats and seasons aren't touched.")
            }
        } footer: {
            Text("Unpublish takes the page offline but leaves the published copy on our servers so you can put it back. This deletes it.")
        }
    }

    // MARK: - Data

    private var hasPublishableClips: Bool {
        (athlete.videoClips ?? []).contains(where: \.isPublishableHighlight)
    }

    /// `showSpinner: false` for pull-to-refresh — swapping the whole form for a
    /// ProgressView under the user's finger reads as a crash, not a refresh.
    private func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        defer { if showSpinner { isLoading = false } }

        // Read the model BEFORE the await — afterwards it may be invalidated.
        let athleteId = athlete.id
        let publishable = (athlete.videoClips ?? []).filter(\.isPublishableHighlight)
        refreshReadiness()

        // What's already on the page wins. Without this the picker re-seeded to
        // newest-8 on every launch, so the next "Update Published Profile" silently
        // threw away the athlete's curation. Clips that have since been deleted or
        // fallen out of publishable state drop out; the stored order is preserved.
        let publishableIDs = Set(publishable.map(\.id))
        let curated = (athlete.recruiting.publishedClipIDs ?? []).filter { publishableIDs.contains($0) }

        // Only a never-published profile falls back to newest-first, so a first
        // publish stays one tap rather than a curation chore.
        let defaultSelection = publishable
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .prefix(RecruitingProfileService.maxHighlights)
            .map(\.id)

        await refreshStatus(athleteId: athleteId)
        if selection.isEmpty {
            selection = curated.isEmpty ? defaultSelection : curated
        }
    }

    /// Recomputes the pre-publish checklist. One blob decode per call rather than
    /// one per render — see the `readiness` declaration.
    private func refreshReadiness() {
        guard !athlete.isDeleted, athlete.modelContext != nil else { return }
        readiness = RecruitingReadiness.items(for: athlete.recruiting,
                                              sport: athlete.sport ?? .baseball)
    }

    /// Re-reads publish state, KEEPING what we already have when the read fails.
    ///
    /// `fetchStatus` returns nil for "no profile yet" but THROWS when Firestore
    /// can't be reached, and `try?` flattened those into the same nil. A single
    /// failed refresh therefore rendered a published profile as never-published
    /// — which silently removes the live link, Unpublish and Reset Link from the
    /// screen. Losing the kill switch to a dropped connection is the same class
    /// of bug as paywalling it: the page stays live while the controls vanish.
    /// Only a successful nil (the doc really is gone) clears it.
    /// On the FIRST load there is no previous value to keep, so a failure leaves
    /// `status` nil — indistinguishable from a legitimate "no profile yet".
    /// `statusLoadFailed` carries that distinction to the UI so an athlete whose
    /// page is live is never shown the never-published layout.
    private func refreshStatus(athleteId: UUID) async {
        do {
            status = try await RecruitingProfileService.shared.fetchStatus(athleteId: athleteId)
            statusLoadFailed = false
        } catch {
            statusLoadFailed = true
            ErrorHandlerService.shared.handle(error,
                                              context: "RecruitingPublishView.refreshStatus",
                                              showAlert: false)
        }
    }

    /// Publish button tap. Free tier gets the paywall instead — the button stays
    /// enabled so there's a visible way to upgrade, and unpublish, right below, is
    /// never gated at all.
    private func publishTapped() {
        guard isPro else {
            Haptics.light()
            showingPaywall = true
            return
        }
        Task { await publish() }
    }

    /// Does the work. Takes no tier check of its own: the paywall's
    /// `onPurchaseCompleted` calls this directly, and it fires just before the
    /// sheet dismisses — `authManager.currentTier` may not have caught up yet, so
    /// re-checking here would bounce the just-paid customer straight back into the
    /// paywall. Every caller has already established the entitlement.
    private func publish() async {
        // `selection` belongs to the athlete this screen loaded for. If the view
        // has since been re-rendered with a different one, publishing would write
        // this athlete's curation and consent stamp against that athlete's doc.
        guard athlete.id == seededAthleteID else { return }
        isWorking = true
        defer {
            isWorking = false
            renditionTotal = 0
            renditionStep = 0
        }

        // Read the model up front — after the awaits below it may be invalidated,
        // and a property read on a deleted @Model traps.
        let athleteId = athlete.id
        let user = athlete.user
        let clips = selection.compactMap { id in
            (athlete.videoClips ?? []).first { $0.id == id }
        }
        // The rules' hasProTier() reads users/{uid}.subscriptionTier, which no
        // client can write — only the syncSubscriptionTier CF sets it, after an
        // AppTransaction fetch, an entitlement JWS and a round trip. A publish
        // resumed from the paywall races that: StoreKit says Pro locally while
        // the server still says free, and the setData is denied. This is the
        // single worst moment in the feature to fail, and each failed attempt
        // also mints another permanently-undeletable recruitingTokens claim.
        // `try?` on purpose — SharedFolderManager.acceptInvitation takes the same
        // position for the identical race: the write below stays authoritative.
        try? await authManager.syncSubscriptionTierToFirestoreAndWait()
        // That await is a suspension point, and the service reads @Model
        // properties off `athlete` before its own first await — a delete landing
        // in between would trap on an invalidated model rather than fail.
        guard !athlete.isDeleted, athlete.modelContext != nil else { return }

        do {
            let result = try await RecruitingProfileService.shared.publish(
                athlete: athlete,
                highlightClips: clips
            ) { done, total in
                renditionStep = done
                renditionTotal = total
            }
            // Record consent only once the page is actually live: stamping it
            // before the write would permanently retire the guardian gate even
            // when publishing failed and nothing was ever shared.
            //
            // The liveness guard comes FIRST: conditions evaluate left to right,
            // and `needsConsent` reads athlete.recruiting — which would trap on a
            // model invalidated during the await above.
            if !athlete.isDeleted, athlete.modelContext != nil {
                var info = athlete.recruiting
                if needsConsent { info.publishConsentAt = Date() }
                // The set that actually reached the page, in page order — so
                // reopening this screen restores the real curation instead of
                // re-seeding to newest-8. RecruitingProfileEditorView.persistIfChanged
                // carries this forward; without that line its autosave erases it.
                info.publishedClipIDs = result.publishedClipIDs
                athlete.recruiting = info      // sets needsSync
                ErrorHandlerService.shared.saveContext(modelContext, caller: "RecruitingPublishView.publish")
            }
            // Reconcile the picker with what actually published. Clips whose
            // Storage objects were reclaimed drop out server-side, and leaving
            // `selection` at the pre-publish set left the picker reading
            // "8 of 8" — at cap, every unselected row disabled — so the athlete
            // couldn't add replacements without blind-deselecting good clips.
            selection = result.publishedClipIDs
            await refreshStatus(athleteId: athleteId)
            let success = PublishSuccess(url: result.url, skipped: result.skippedClipCount)
            // A publish resumed from the paywall can finish before its sheet is
            // off screen — park the result until then (see pendingSuccess).
            if showingPaywall {
                pendingSuccess = success
            } else {
                publishSuccess = success
            }
            // `user` was captured pre-await, but it's a @Model reference, not a
            // value — syncAthletes reads its properties, so it needs the same
            // liveness check as the athlete.
            if let user, !user.isDeleted, user.modelContext != nil {
                Task { try? await SyncCoordinator.shared.syncAthletes(for: user) }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't publish your profile. Check your connection and try again."
            if showingPaywall {
                pendingError = message
            } else {
                errorMessage = message
            }
            ErrorHandlerService.shared.handle(error, context: "RecruitingPublishView.publish", showAlert: false)
        }
    }

    private func unpublish() async {
        isWorking = true
        defer { isWorking = false }
        let athleteId = athlete.id
        let sport = (athlete.sport ?? .baseball).rawValue
        do {
            try await RecruitingProfileService.shared.unpublish(athleteId: athleteId, sport: sport)
            await refreshStatus(athleteId: athleteId)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't unpublish. Check your connection and try again."
            ErrorHandlerService.shared.handle(error, context: "RecruitingPublishView.unpublish", showAlert: false)
        }
    }

    /// Deletes the published doc and the headshot object. See `deleteDataSection`
    /// for what this does and doesn't remove.
    private func deleteProfileData() async {
        // Same witness `publish()` uses, and for a sharper reason: if the view was
        // re-rendered with a different athlete while this screen stayed pushed, the
        // live link and view count on screen still belong to the athlete it loaded
        // for, while `athlete.id` already points at the new one — so the tap would delete
        // a profile other than the one being displayed. Irreversible, so drop it.
        guard athlete.id == seededAthleteID else { return }
        // `deleteProfileDoc` carries no connectivity guard of its own, on purpose:
        // Athlete.delete fires it best-effort, and offline it SHOULD ride
        // Firestore's local queue rather than be skipped — skipping would leave a
        // deleted athlete's page live on the internet. Here it's a foreground
        // action behind `isWorking`, and a Firestore delete only completes on
        // backend commit, so without this guard the screen would hang with
        // Unpublish and Reset Link both disabled: the same lost-kill-switch
        // failure P1.6 fixed on the publish path.
        guard ConnectivityMonitor.shared.isConnected else {
            errorMessage = RecruitingPublishError.offline.errorDescription
            return
        }
        isWorking = true
        defer { isWorking = false }

        // Snapshot every @Model read before the first await — a concurrent delete
        // that invalidates the model would trap on a later property read.
        let athleteId = athlete.id
        let sport = (athlete.sport ?? .baseball).rawValue
        let ownerUID = athlete.user?.firebaseAuthUid
        let hadHeadshot = athlete.recruiting.headshotCloudURL != nil

        do {
            try await RecruitingProfileService.shared.deleteProfileDoc(athleteId: athleteId)
            if hadHeadshot {
                // Best-effort: the page — the part that was public — is already
                // gone. Failing the whole action over a leftover JPEG would leave
                // the athlete no way to retry the half that succeeded, since the
                // button hides once `status` is nil.
                try? await VideoCloudManager.shared.deleteRecruitingHeadshot(
                    athleteId: athleteId, ownerUID: ownerUID
                )
                // The stored download URL 404s now, so leaving it behind shows a
                // broken headshot in the editor with nothing to explain why. Safe
                // to clear across devices: only publishConsentAt and
                // publishedClipIDs are nil-protected by mergedRecruitingBlob, so
                // this one propagates as a normal last-write-wins edit.
                if !athlete.isDeleted, athlete.modelContext != nil {
                    var info = athlete.recruiting
                    info.headshotCloudURL = nil
                    athlete.recruiting = info      // sets needsSync
                    ErrorHandlerService.shared.saveContext(
                        modelContext, caller: "RecruitingPublishView.deleteProfileData"
                    )
                    // The checklist was computed at load, when the headshot still
                    // existed — without this it would sit there reporting
                    // "Headshot ✓" immediately after deleting the headshot.
                    refreshReadiness()
                    if let user = athlete.user, !user.isDeleted, user.modelContext != nil {
                        Task { try? await SyncCoordinator.shared.syncAthletes(for: user) }
                    }
                }
            }
            // Set directly rather than via refreshStatus: the doc is gone, so a
            // re-read can only return nil — but on a flaky connection it could
            // THROW instead, arming statusLoadFailed and raising "couldn't check
            // whether this profile is live" over a profile just deleted on purpose.
            status = nil
            statusLoadFailed = false
            AnalyticsService.shared.trackRecruitingProfileDataDeleted(
                athleteID: athleteId.uuidString, sport: sport
            )
            Haptics.light()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't delete your profile data. Check your connection and try again."
            ErrorHandlerService.shared.handle(error, context: "RecruitingPublishView.deleteProfileData", showAlert: false)
        }
    }

    private func resetLink() async {
        isWorking = true
        defer { isWorking = false }
        let athleteId = athlete.id
        let sport = (athlete.sport ?? .baseball).rawValue
        do {
            let newToken = try await RecruitingProfileService.shared.resetLink(athleteId: athleteId, sport: sport)
            // Swap the token locally instead of re-reading. A failed re-read
            // would leave the OLD token on screen — a link that is now dead —
            // and every surface here (URL line, QR sheet, ShareLink, the bio
            // blurb, the mailto body) would hand out a 404. The write already
            // succeeded, so this is the authoritative value; the counts are
            // untouched by a reset and carry over as-is.
            if let current = status {
                status = RecruitingPublishStatus(
                    isPublished: current.isPublished,
                    shareToken: newToken,
                    viewCount: current.viewCount,
                    viewsThisWeek: current.viewsThisWeek,
                    lastViewedAt: current.lastViewedAt,
                    publishedAt: current.publishedAt,
                    // resetLink stamps updatedAt server-side; mirror it locally
                    // rather than keeping the pre-reset value, which would make
                    // the editor's "updated" date older than an action the athlete
                    // just took.
                    updatedAt: Date()
                )
            }
            Haptics.light()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't reset your link. Check your connection and try again."
            ErrorHandlerService.shared.handle(error, context: "RecruitingPublishView.resetLink", showAlert: false)
        }
    }

    private func coachEmailURL(url: URL) -> URL? {
        RecruitingShareTools.coachEmailURL(
            // Plain `name`, NOT nameWithSportIfShared: the subject already appends
            // `subline`, which names the sport since P4.2, so qualifying the name
            // would print it twice — "Jordan Smith · Golf — Class of 2027 · Golf
            // — Game Film". The published page's <h1> is left alone for the same
            // reason; its subline carries the sport.
            athleteName: athlete.name,
            info: athlete.recruiting,
            sport: athlete.sport ?? .baseball,
            url: url
        )
    }
}
