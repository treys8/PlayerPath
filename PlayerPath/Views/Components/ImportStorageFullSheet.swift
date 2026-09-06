//
//  ImportStorageFullSheet.swift
//  PlayerPath
//
//  Shown when a bulk import stops because the athlete's projected cloud storage
//  is exhausted. This replaced a 2.5-second gray toast: hitting the cap during a
//  camera-roll backfill is the highest-intent moment in the product, and it used
//  to be a dead end that named no number and offered no way forward.
//
//  Serves both media pipelines — `mediaNoun` is the only thing that differs.
//

import SwiftUI

/// Everything the sheet needs to state real figures. `Identifiable` so callers
/// present it with `.sheet(item:)`, which cannot land in the "presented but with
/// nothing to show" state a stale `isPresented` bool can.
struct ImportStorageFullContext: Identifiable {
    let id = UUID()
    let outcome: BulkImportOutcome
    let user: User
    let snapshot: ProjectedCloudStorage.Snapshot
    /// Singular noun for the media being imported — "video" or "photo".
    let mediaNoun: String
}

struct ImportStorageFullSheet: View {
    let context: ImportStorageFullContext
    /// Called once a purchase completes and this sheet is on its way out. The
    /// caller must PARK this and act after its own `onDismiss` — presenting the
    /// resumed import sheet while this one is still on screen is silently
    /// dropped by SwiftUI and leaves the presenter unable to show any sheet again.
    let onResumeRequested: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.ppAccent) private var ppAccent

    @State private var showingPaywall = false
    /// The tier to sell, captured when the button is tapped.
    ///
    /// `upgradeTarget` is derived live from `SubscriptionGate.effectiveAthleteTier`,
    /// and this view's body re-evaluates on any parent update. If that happened
    /// after a Free→Plus purchase landed, a rebuilt paywall would carry
    /// `requiredTier: .pro`, `ImprovedPaywallView`'s `newTier >= requiredTier`
    /// check would fail, and the user who just paid would get no dismissal and no
    /// resume. Snapshot it once instead.
    @State private var purchaseTarget: SubscriptionTier?
    /// Set from the paywall's completion callback, acted on in its `onDismiss`.
    /// Doing anything presentational inside `onPurchaseCompleted` races the
    /// paywall's own `dismiss()`, which fires on the very next line.
    @State private var resumeRequested = false

    // MARK: - Derived copy

    private var outcome: BulkImportOutcome { context.outcome }
    private var snapshot: ProjectedCloudStorage.Snapshot { context.snapshot }

    private var remainingCount: Int { outcome.remaining.count }
    /// Items this run was actually being asked to bring in. Excludes duplicates:
    /// counting them would tell a user on their second backfill sitting that 51
    /// photos "couldn't be imported" when 40 were already in their library.
    private var totalCount: Int {
        outcome.attempted - outcome.skippedDuplicates + remainingCount
    }

    /// The next tier up from what the athlete effectively has. Nil when they are
    /// already on the top tier — hard-coding `.plus` here would show a Plus
    /// subscriber a "buy Plus" screen and a Pro subscriber a plan they own.
    private var upgradeTarget: SubscriptionTier? {
        switch SubscriptionGate.effectiveAthleteTier {
        case .free: return .plus
        case .plus: return .pro
        case .pro:  return nil
        }
    }

    private var currentPlanName: String {
        SubscriptionGate.effectiveAthleteTier.displayName
    }

    /// Rough size of what is left, extrapolated from what this run actually
    /// imported. Only offered when there is a real basis for it — the items that
    /// never ran were never loaded, so their true size is unknown.
    private var estimatedRemainingBytes: Int64? {
        guard outcome.succeeded > 0, remainingCount > 0 else { return nil }
        let average = outcome.importedBytes / Int64(outcome.succeeded)
        guard average > 0 else { return nil }
        return average * Int64(remainingCount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Divider().overlay(Theme.divider)
                    facts
                    actions
                }
                .padding(24)
            }
            .background(Theme.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingPaywall, onDismiss: paywallDismissed) {
            ImprovedPaywallView(
                user: context.user,
                requiredTier: purchaseTarget,
                onPurchaseCompleted: { resumeRequested = true }
            )
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: upgradeTarget == nil ? "externaldrive.badge.xmark" : "icloud.slash")
                .font(.system(size: 36))
                .foregroundStyle(Theme.warning)

            Text(upgradeTarget == nil ? "Free Up Space" : "Storage Full")
                .font(.ppTitle)
                .foregroundStyle(Theme.textPrimary)

            if outcome.succeeded > 0 {
                Text("Imported \(outcome.succeeded) of \(totalCount).")
                    .font(.ppBody)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("^[\(totalCount) \(context.mediaNoun)](inflect: true) couldn't be imported.")
                    .font(.ppBody)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Certain figures first: both of these are measured, not estimated.
            factRow(
                "You have \(StorageManager.formatBytes(snapshot.remainingBytes)) left of your \(currentPlanName) plan's \(StorageManager.formatBytes(snapshot.limitBytes))."
            )

            if outcome.blockedItemBytes > 0 {
                factRow(
                    "The next \(context.mediaNoun) alone needs \(StorageManager.formatBytes(outcome.blockedItemBytes))."
                )
            }

            if outcome.skippedDuplicates > 0 {
                factRow(
                    "^[\(outcome.skippedDuplicates) \(context.mediaNoun)](inflect: true) in your selection ^[was](inflect: true) already in your library, and cost nothing."
                )
            }

            if let estimate = estimatedRemainingBytes {
                factRow(
                    "The remaining ^[\(remainingCount) \(context.mediaNoun)](inflect: true) need roughly \(StorageManager.formatBytes(estimate))."
                )
            }

            // MANDATORY when it applies. This gate counts bytes that have not
            // reached the cloud yet, so a user with auto-upload off sees a number
            // that doesn't match anything the Storage screen shows them. Without
            // this line the block reads as a bug rather than as a real limit.
            if snapshot.pendingLocalBytes > 0 {
                factRow(
                    "\(StorageManager.formatBytes(snapshot.pendingLocalBytes)) of what you already have is still waiting to upload, and is counted here."
                )
            }
        }
    }

    private func factRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Theme.textTertiary)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(text)
                .font(.ppSubheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if let target = upgradeTarget {
                Button {
                    purchaseTarget = target
                    showingPaywall = true
                } label: {
                    Text("Upgrade to \(target.displayName)")
                        .font(.ppHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(ppAccent)

                if remainingCount > 0 {
                    Text("We'll finish the remaining ^[\(remainingCount) \(context.mediaNoun)](inflect: true) automatically.")
                        .font(.ppCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Button {
                dismiss()
                NotificationCenter.default.post(name: .navigateToCloudStorage, object: nil)
            } label: {
                Text("Manage Storage")
                    .font(.ppCallout)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.bordered)

            Button("Not Now") { dismiss() }
                .font(.ppCallout)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
        }
        .padding(.top, 4)
    }

    // MARK: - Resume

    private func paywallDismissed() {
        guard resumeRequested else { return }
        resumeRequested = false
        // Hand the request up, then get out of the way. The caller re-presents
        // the import sheet from ITS onDismiss, once this sheet is fully gone.
        onResumeRequested()
        dismiss()
    }
}
