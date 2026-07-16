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

    private var isPro: Bool { authManager.currentTier >= .pro }
    private var isPublished: Bool { status?.isPublished == true }
    private var needsConsent: Bool { athlete.recruiting.publishConsentAt == nil }
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
                }
            }
            .padding(.vertical, 4)
        } footer: {
            if let status {
                Text(viewCountText(status.viewCount))
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
            Label(isPublished
                  ? "Your profile is offline because Pro ended. Renew to bring it back — your link doesn't change, so anything you've already sent to coaches will work again."
                  : "Publishing a public profile is a Pro feature.",
                  systemImage: "crown.fill")
                .font(.bodySmall)
                .foregroundStyle(.secondary)
        }
    }

    private var publishSection: some View {
        Section {
            Button {
                Task { await publish() }
            } label: {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(isPublished ? "Update Published Profile" : "Publish Profile")
                        .font(.headingMedium)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canPublish || !isPro)
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
        // Default to the athlete's newest publishable highlights, so a first
        // publish is one tap rather than a curation chore.
        let athleteId = athlete.id
        let defaultSelection = (athlete.videoClips ?? [])
            .filter(\.isPublishableHighlight)
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .prefix(RecruitingProfileService.maxHighlights)
            .map(\.id)

        status = try? await RecruitingProfileService.shared.fetchStatus(athleteId: athleteId)
        if selection.isEmpty {
            selection = defaultSelection
        }
    }

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
            _ = try await RecruitingProfileService.shared.publish(athlete: athlete, highlightClips: clips)
            // Record consent only once the page is actually live: stamping it
            // before the write would permanently retire the guardian gate even
            // when publishing failed and nothing was ever shared.
            //
            // The liveness guard comes FIRST: conditions evaluate left to right,
            // and `needsConsent` reads athlete.recruiting — which would trap on a
            // model invalidated during the await above.
            if !athlete.isDeleted, athlete.modelContext != nil, needsConsent {
                var info = athlete.recruiting
                info.publishConsentAt = Date()
                athlete.recruiting = info      // sets needsSync
                ErrorHandlerService.shared.saveContext(modelContext, caller: "RecruitingPublishView.publish")
            }
            status = try? await RecruitingProfileService.shared.fetchStatus(athleteId: athleteId)
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

    private func viewCountText(_ count: Int) -> String {
        switch count {
        case 0: return "Not viewed yet."
        case 1: return "Viewed 1 time."
        default: return "Viewed \(count) times."
        }
    }
}
