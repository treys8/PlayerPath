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

    @State private var status: RecruitingPublishStatus?
    @State private var selection: [UUID] = []
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var consentAcknowledged = false
    @State private var showingUnpublishConfirm = false
    @State private var showingPaywall = false
    @State private var showingQR = false
    /// Non-nil right after a successful publish — drives the success sheet.
    /// Carries the URL + skipped-clip count so the sheet needs no re-fetch.
    @State private var publishSuccess: PublishSuccess?
    /// Success that landed while the paywall sheet was still up (a fast publish
    /// resumed from onPurchaseCompleted can beat the dismiss animation).
    /// Presenting over a live sibling sheet gets silently dropped by SwiftUI —
    /// and the binding would then stay "presented", blocking every later sheet
    /// from this view. Parked here and promoted once the paywall is gone.
    @State private var pendingSuccess: PublishSuccess?

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
                if isPublished, let url = status?.shareURL {
                    liveLinkSection(url: url)
                    // Stats about a dark page would read as "coaches can still
                    // see this" — only a live (Pro) page shows its numbers.
                    if isPro { activitySection }
                }
                clipsSection
                if needsConsent { consentSection }
                // Shown when published too: a lapsed-Pro account would otherwise
                // face a disabled "Update" button with no explanation of why.
                if !isPro { upgradeSection }
                publishSection
                if isPublished { unpublishSection }
            }
        }
        .navigationTitle("Share Profile")
        .navigationBarTitleDisplayMode(.inline)
        .tint(ppAccent)
        .ppAccent(for: athlete.sport)
        .task { await load() }
        .onAppear {
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
                RecruitingQRCodeView(athleteName: athlete.name, url: url)
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
            VStack(alignment: .leading, spacing: 10) {
                // isPublished alone doesn't mean a coach can open it:
                // serveRecruitingProfile re-checks the owner's tier per render, so
                // a lapsed account's page is dark even though the flag is still
                // true. Claiming "live" here would be a lie the athlete only
                // discovers when a coach tells them the link is broken.
                Label(isPro ? "Your profile is live" : "Your profile is offline",
                      systemImage: isPro ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.headingMedium)
                    .foregroundStyle(isPro ? ppAccent : Theme.warning)
                Text(url.absoluteString)
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                // No sharing while the page is dark: handing a college coach a link
                // that 404s is worse than not sharing at all. The URL still shows
                // (it's theirs, and it comes back on renewal) — just not the verbs
                // that put it in someone else's inbox.
                if isPro {
                    HStack(spacing: 12) {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            UIPasteboard.general.string = url.absoluteString
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                    HStack(spacing: 12) {
                        Button {
                            showingQR = true
                        } label: {
                            Label("QR Code", systemImage: "qrcode")
                        }
                        .buttonStyle(.bordered)

                        if let emailURL = coachEmailURL(url: url) {
                            Button {
                                // No mail app configured → open() fails with no
                                // UI at all. Falling back to the pasteboard beats
                                // a prominent button that does nothing.
                                UIApplication.shared.open(emailURL, options: [:]) { opened in
                                    if !opened {
                                        UIPasteboard.general.string = url.absoluteString
                                        errorMessage = "No mail app is set up on this device — your profile link was copied instead."
                                    }
                                }
                            } label: {
                                Label("Email a Coach", systemImage: "envelope")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } footer: {
            if isPro {
                Text("For a social bio: tap and hold to copy.\n\(RecruitingShareTools.bioBlurb(sport: athlete.sport, url: url))")
                    .textSelection(.enabled)
            }
        }
    }

    /// Total / this-week / last-viewed. The counts come off the profile doc
    /// (written by serveRecruitingProfile, digested by recruitingViewDigest);
    /// link unfurlers and bots are already excluded server-side.
    private var activitySection: some View {
        Section("Profile Activity") {
            if let status {
                LabeledContent("Total views", value: "\(status.viewCount)")
                LabeledContent("This week", value: "\(status.viewsThisWeek)")
                if let lastViewedAt = status.lastViewedAt {
                    LabeledContent("Last viewed",
                                   value: lastViewedAt.formatted(.relative(presentation: .named)))
                }
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
        } footer: {
            if isPublished {
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
        } footer: {
            Text("Your link never changes, so a coach's bookmark still works if you publish again.")
        }
    }

    // MARK: - Data

    private var hasPublishableClips: Bool {
        (athlete.videoClips ?? []).contains(where: \.isPublishableHighlight)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // Read the model BEFORE the await — afterwards it may be invalidated.
        let athleteId = athlete.id
        let publishable = (athlete.videoClips ?? []).filter(\.isPublishableHighlight)

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

        status = try? await RecruitingProfileService.shared.fetchStatus(athleteId: athleteId)
        if selection.isEmpty {
            selection = curated.isEmpty ? defaultSelection : curated
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
        isWorking = true
        defer { isWorking = false }

        // Read the model up front — after the awaits below it may be invalidated,
        // and a property read on a deleted @Model traps.
        let athleteId = athlete.id
        let user = athlete.user
        let clips = selection.compactMap { id in
            (athlete.videoClips ?? []).first { $0.id == id }
        }
        do {
            let result = try await RecruitingProfileService.shared.publish(athlete: athlete, highlightClips: clips)
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
            status = try? await RecruitingProfileService.shared.fetchStatus(athleteId: athleteId)
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
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't publish your profile. Check your connection and try again."
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
            status = try? await RecruitingProfileService.shared.fetchStatus(athleteId: athleteId)
        } catch {
            errorMessage = "Couldn't unpublish. Check your connection and try again."
            ErrorHandlerService.shared.handle(error, context: "RecruitingPublishView.unpublish", showAlert: false)
        }
    }

    private func coachEmailURL(url: URL) -> URL? {
        RecruitingShareTools.coachEmailURL(
            athleteName: athlete.name,
            info: athlete.recruiting,
            isGolf: (athlete.sport ?? .baseball) == .golf,
            url: url
        )
    }
}
