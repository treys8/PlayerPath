//
//  RecruitingProfileService.swift
//  PlayerPath
//
//  Publishes an athlete's recruiting profile to `recruitingProfiles/{athleteId}` —
//  the snapshot behind the public page at profiles.playerpath.net/p/{shareToken}.
//
//  Design notes:
//  • Doc ID is the athlete's canonical UUID, so publish is an idempotent upsert
//    (no lookup query, no duplicate-doc risk).
//  • The doc stores Storage PATHS, never URLs. serveRecruitingProfile signs them
//    per request with a short expiry, so nothing durable in Firestore is fetchable.
//  • Display strings are built here from the same helpers the in-app preview uses,
//    so the Cloud Function stays a dumb renderer and the page can never word
//    something differently from the preview.
//  • PII keys are OMITTED unless their opt-in flag is on — never written as null.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import os

private let recruitingLog = Logger(subsystem: "com.playerpath.app", category: "RecruitingProfile")

/// Publish state for the share UI.
struct RecruitingPublishStatus {
    let isPublished: Bool
    let shareToken: String
    let viewCount: Int
    let viewsThisWeek: Int
    let lastViewedAt: Date?
    let publishedAt: Date?

    var shareURL: URL? { RecruitingProfileService.shareURL(for: shareToken) }
}

/// Outcome of a publish — the link, plus anything that didn't make it onto the page.
struct RecruitingPublishResult {
    let url: URL
    /// The clips that actually reached the page, in page order (first = hero).
    /// Persisted by the caller so a relaunch reopens the athlete's real curation.
    let publishedClipIDs: [UUID]
    /// Clips the athlete picked whose file isn't in Storage, so they were left off.
    /// Surfaced rather than swallowed: the Cloud Function drops an unsignable clip
    /// with nothing but a server log, and the athlete would never learn their page
    /// is short a clip.
    let skippedClipCount: Int
}

enum RecruitingPublishError: LocalizedError {
    case notSignedIn
    case accountMismatch
    case noPublishableClips
    case couldNotClaimLink

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in required to publish your profile."
        case .accountMismatch:
            return "This profile belongs to a different account. Sign out and back in, then try again."
        case .noPublishableClips:
            return "Your highlights are still uploading. This usually finishes on Wi-Fi."
        case .couldNotClaimLink:
            return "Couldn't reserve a link for your profile. Check your connection and try again."
        }
    }
}

@MainActor
final class RecruitingProfileService {

    static let shared = RecruitingProfileService()
    private init() {}

    private let db = Firestore.firestore()

    /// Where published profiles are served. Firebase Hosting rewrites `/p/**` to
    /// the serveRecruitingProfile function. Before the custom domain's DNS is
    /// live, point this at the project's default `<project>.web.app` host — the
    /// links work identically, and this constant is the only thing that changes.
    static let publicBaseURL = "https://profiles.playerpath.net"

    /// Max clips on a published page — bounds page weight and signed-URL egress.
    /// Mirrored by the `highlights.size() <= 8` check in firestore.rules.
    static let maxHighlights = 8

    static func shareURL(for token: String) -> URL? {
        URL(string: "\(publicBaseURL)/p/\(token)")
    }

    // MARK: - Publish

    /// Snapshots the athlete's bio, stats, and chosen clips into the published doc
    /// and returns the public link. Reuses the existing share token when one
    /// exists, so republishing never breaks a coach's bookmark.
    @discardableResult
    func publish(athlete: Athlete, highlightClips: [VideoClip]) async throws -> RecruitingPublishResult {
        // Storage paths are anchored on the AUTH uid, because that is what every
        // uploader used (VideoCloudManager.uploadVideo et al). The local User row's
        // cached firebaseAuthUid is a copy that can go stale — AuthenticatedFlow's
        // UID-mismatch branch can leave a second User row behind — and publishing
        // under a stale uid would write paths into a namespace nothing was ever
        // uploaded to. Rules would then reject the doc (its userId wouldn't match
        // request.auth.uid) and the athlete would see an unexplained failure, so
        // catch it here and say what actually happened.
        guard let ownerUID = Auth.auth().currentUser?.uid, !ownerUID.isEmpty else {
            throw RecruitingPublishError.notSignedIn
        }
        // Snapshot every @Model property BEFORE the first await: a concurrent
        // delete that invalidates the model mid-await would trap on a later read.
        let modelUID = athlete.user?.firebaseAuthUid
        guard modelUID == nil || modelUID == ownerUID else {
            recruitingLog.error("Publish blocked: local user uid disagrees with the signed-in account")
            throw RecruitingPublishError.accountMismatch
        }
        let athleteId = athlete.id
        let name = athlete.name
        let sport = (athlete.sport ?? .baseball)
        let info = athlete.recruiting
        let golfStats = sport == .golf ? RecruitingGolfStats.compute(for: athlete) : nil

        // Re-check the upload gate at write time: a clip that lost its cloud copy
        // would render as a broken player on the coach's page.
        // Carries the clip id alongside its payload so the caller can persist the
        // set that ACTUALLY reached the page, not the set that was selected.
        let candidates = highlightClips
            .prefix(Self.maxHighlights)
            .compactMap { clip -> (id: UUID, payload: [String: Any])? in
                guard clip.isUploaded, clip.cloudURL != nil, !clip.fileName.isEmpty else { return nil }
                return (clip.id, Self.highlightPayload(for: clip, ownerUID: ownerUID))
            }
        guard !candidates.isEmpty else {
            throw RecruitingPublishError.noPublishableClips
        }

        // `isUploaded` is a local flag; it can outlive the object (quota sweep,
        // coach-side delete, a wipe on another device). Nothing records the real
        // storage path, so the only way to know a clip will actually play is to ask
        // Storage before publishing rather than let the page render short.
        let missing = await Self.missingStoragePaths(
            candidates.compactMap { $0.payload["videoStoragePath"] as? String }
        )
        let kept = missing.isEmpty ? candidates : candidates.filter {
            !missing.contains($0.payload["videoStoragePath"] as? String ?? "")
        }
        guard !kept.isEmpty else {
            throw RecruitingPublishError.noPublishableClips
        }
        let highlights = kept.map(\.payload)
        let publishedClipIDs = kept.map(\.id)
        let skippedClipCount = candidates.count - kept.count

        let docRef = db.collection(FC.recruitingProfiles).document(athleteId.uuidString)
        // NOT `try?`: every decision below depends on this read. Swallowing a
        // failure would mint a fresh shareToken on a republish — which the rules'
        // token-immutability check then rejects, surfacing as an unexplainable
        // "couldn't publish" — and would reset viewCount to zero.
        let existing = try await docRef.getDocument()
        let existingData = existing.exists ? existing.data() : nil

        // The write is a full overwrite, NOT a merge: a merge would leave a
        // previously-published PII key in place after the athlete toggles it off.
        // So counters that only the server touches are carried forward by hand.
        // A view landing between this read and the write is lost — an acceptable
        // trade for a vanity counter, where leaking a retracted phone number isn't.
        //
        // Republishing reuses the existing token (a coach's bookmark must keep
        // working); a first publish has to claim one before it can be used.
        let shareToken: String
        if let existingToken = existingData?["shareToken"] as? String {
            shareToken = existingToken
        } else {
            shareToken = try await claimShareToken(athleteId: athleteId, ownerUID: ownerUID)
        }

        var data: [String: Any] = [
            "userId": ownerUID,
            "athleteId": athleteId.uuidString,
            "shareToken": shareToken,
            "isPublished": true,
            "sport": sport.rawValue,
            "name": name,
            "highlights": highlights,
            "viewCount": existingData?["viewCount"] as? Int ?? 0,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let lastViewedAt = existingData?["lastViewedAt"] {
            data["lastViewedAt"] = lastViewedAt
        }
        // Analytics fields only serveRecruitingProfile / recruitingViewDigest
        // write. Any server-owned field NOT carried here is erased by this
        // full-overwrite publish — dailyViews powers "views this week", and the
        // notification watermarks stop a republish from re-arming the instant
        // push or making the next digest re-count already-notified views.
        for key in ["dailyViews", "lastNotifiedAt", "notifiedViewCount"] {
            if let value = existingData?[key] {
                data[key] = value
            }
        }
        data["publishedAt"] = existingData?["publishedAt"] ?? FieldValue.serverTimestamp()
        data["createdAt"] = existingData?["createdAt"] ?? FieldValue.serverTimestamp()

        Self.applyBio(info, sport: sport, to: &data)
        if let golfStats, golfStats.hasScores {
            data["golfStats"] = Self.golfPayload(golfStats)
        }
        if let headshotPath = Self.headshotPath(info: info, athleteId: athleteId, ownerUID: ownerUID) {
            data["headshotPath"] = headshotPath
        }

        try await docRef.setData(data)

        AnalyticsService.shared.trackRecruitingProfilePublished(
            athleteID: athleteId.uuidString,
            sport: sport.rawValue,
            clipCount: highlights.count,
            isFirstPublish: existingData == nil
        )
        recruitingLog.info("Published recruiting profile for athlete \(athleteId.uuidString, privacy: .public)")
        if skippedClipCount > 0 {
            recruitingLog.warning("Published with \(skippedClipCount, privacy: .public) clip(s) missing from Storage")
        }

        guard let url = Self.shareURL(for: shareToken) else {
            // Unreachable in practice (constant host + UUID path), but "sign in
            // required" would be a nonsense thing to tell someone here.
            throw RecruitingPublishError.couldNotClaimLink
        }
        return RecruitingPublishResult(url: url,
                                      publishedClipIDs: publishedClipIDs,
                                      skippedClipCount: skippedClipCount)
    }

    /// Which of these Storage paths have no object behind them.
    ///
    /// Only a genuine `objectNotFound` counts — mirrors the check used throughout
    /// VideoCloudManager. A timeout or an offline device must NOT shrink the page:
    /// treating a transient failure as "gone" would quietly publish fewer clips
    /// than the athlete curated, which is the exact failure this exists to stop.
    private static func missingStoragePaths(_ paths: [String]) async -> Set<String> {
        guard !paths.isEmpty else { return [] }
        return await withTaskGroup(of: (String, Bool).self) { group in
            for path in paths {
                group.addTask {
                    do {
                        _ = try await Storage.storage().reference(withPath: path).getMetadata()
                        return (path, false)
                    } catch {
                        let nsError = error as NSError
                        let isGone = nsError.domain == "FIRStorageErrorDomain"
                            && nsError.code == StorageErrorCode.objectNotFound.rawValue
                        return (path, isGone)
                    }
                }
            }
            var missing: Set<String> = []
            for await (path, isGone) in group where isGone { missing.insert(path) }
            return missing
        }
    }

    // MARK: - Share token

    /// Reserves a share token before it's written onto the profile.
    ///
    /// The claim doc is keyed by the token itself and is create-only, so Firestore's
    /// "create fails if the doc exists" IS the atomic lock — first writer owns the
    /// token forever. `firestore.rules` won't let a profile carry a token this
    /// account doesn't hold a claim on, which is what stops someone republishing
    /// under an athlete's already-circulated link.
    ///
    /// v4 UUIDs don't collide by accident, so a failed claim means someone else
    /// holds that token; mint a fresh one rather than surfacing an error the user
    /// can't act on. (An abandoned claim — a network failure between the claim and
    /// the profile write — leaves a tiny orphan doc; the next attempt mints a new
    /// token, so nothing is stuck.)
    private func claimShareToken(athleteId: UUID, ownerUID: String) async throws -> String {
        for _ in 0..<3 {
            let token = UUID().uuidString
            do {
                try await db.collection(FC.recruitingTokens).document(token).setData([
                    "userId": ownerUID,
                    "athleteId": athleteId.uuidString,
                    "createdAt": FieldValue.serverTimestamp()
                ])
                return token
            } catch {
                recruitingLog.warning("Share-token claim collided, retrying: \(error.localizedDescription, privacy: .public)")
                continue
            }
        }
        throw RecruitingPublishError.couldNotClaimLink
    }

    // MARK: - Unpublish

    /// Takes the public page down. Deliberately NOT tier-gated — a lapsed-Pro
    /// account must always be able to pull its athlete's page (firestore.rules
    /// allows `isPublished == false` at any tier for the same reason).
    ///
    /// Takes plain values rather than the `Athlete`: callers reach this after an
    /// await, and reading a @Model property on an invalidated model traps.
    func unpublish(athleteId: UUID, sport: String) async throws {
        try await db.collection(FC.recruitingProfiles).document(athleteId.uuidString)
            .updateData([
                "isPublished": false,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        AnalyticsService.shared.trackRecruitingProfileUnpublished(
            athleteID: athleteId.uuidString, sport: sport
        )
        recruitingLog.info("Unpublished recruiting profile for athlete \(athleteId.uuidString, privacy: .public)")
    }

    // MARK: - Status

    /// Current publish state, or nil when this athlete has never been published.
    /// Takes an id, not the model — see `unpublish` for why.
    func fetchStatus(athleteId: UUID) async throws -> RecruitingPublishStatus? {
        let snapshot = try await db.collection(FC.recruitingProfiles)
            .document(athleteId.uuidString).getDocument()
        guard let data = snapshot.data(), let shareToken = data["shareToken"] as? String else {
            return nil
        }
        return RecruitingPublishStatus(
            isPublished: data["isPublished"] as? Bool ?? false,
            shareToken: shareToken,
            viewCount: data["viewCount"] as? Int ?? 0,
            viewsThisWeek: Self.viewsThisWeek(from: data["dailyViews"] as? [String: Any]),
            lastViewedAt: (data["lastViewedAt"] as? Timestamp)?.dateValue(),
            publishedAt: (data["publishedAt"] as? Timestamp)?.dateValue()
        )
    }

    /// Sums the trailing 7 days of the CF-written `dailyViews` map. Keys are
    /// UTC "yyyy-MM-dd" (serveRecruitingProfile.utcDayKey), so the cutoff is
    /// computed in UTC too — string comparison works because the format is
    /// big-endian. Stale keys past the digest's 14-day pruning are ignored by
    /// construction.
    private static func viewsThisWeek(from dailyViews: [String: Any]?) -> Int {
        guard let dailyViews, !dailyViews.isEmpty else { return 0 }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let cutoff = formatter.string(from: Date().addingTimeInterval(-6 * 24 * 3600))
        return dailyViews.reduce(0) { total, entry in
            entry.key >= cutoff ? total + ((entry.value as? Int) ?? 0) : total
        }
    }

    // MARK: - Delete

    /// Hard-deletes the published doc so a public page can never outlive its
    /// athlete. Best-effort: callers fire this alongside the local delete.
    func deleteProfileDoc(athleteId: UUID) async throws {
        try await db.collection(FC.recruitingProfiles).document(athleteId.uuidString).delete()
    }

    // MARK: - Payload builders

    /// Storage path of the headshot. Derived from the deterministic upload path
    /// (VideoCloudManager.uploadRecruitingHeadshot) rather than parsed out of the
    /// stored download URL — the URL carries an access token we don't want in the
    /// published doc, and a path is what the CF needs to sign.
    private static func headshotPath(info: RecruitingInfo, athleteId: UUID, ownerUID: String) -> String? {
        guard info.headshotCloudURL != nil else { return nil }
        return "recruiting_headshots/\(ownerUID)/\(athleteId.uuidString).jpg"
    }

    private static func highlightPayload(for clip: VideoClip, ownerUID: String) -> [String: Any] {
        var payload: [String: Any] = [
            "videoStoragePath": "athlete_videos/\(ownerUID)/\(clip.fileName)",
            "label": clip.recruitingLabel
        ]
        // Thumbnail path mirrors uploadAthleteVideoThumbnail's naming. The CF drops
        // the poster if the object isn't there, so an un-thumbnailed clip is fine.
        let base = (clip.fileName as NSString).deletingPathExtension
        if !base.isEmpty {
            payload["thumbnailStoragePath"] = "athlete_videos/\(ownerUID)/thumbnails/\(base)_thumbnail.jpg"
        }
        if let duration = clip.duration {
            payload["durationSeconds"] = duration
        }
        return payload
    }

    /// Bio + measurables + contact, with every opt-in enforced. Keys are omitted
    /// rather than nulled so an un-shared field leaves no trace in the doc.
    private static func applyBio(_ info: RecruitingInfo, sport: Sport, to data: inout [String: Any]) {
        let isGolf = sport == .golf
        if let gradYear = info.gradYear { data["gradYear"] = gradYear }
        if let subline = info.subline(isGolf: isGolf) { data["subline"] = subline }
        if let physicalLine = info.physicalLine(isGolf: isGolf) { data["physicalLine"] = physicalLine }
        if let schoolLine = info.schoolLine { data["schoolLine"] = schoolLine }
        if let bio = info.bio, !bio.isEmpty { data["bio"] = bio }

        let measurables = info.measurableItems
        if !measurables.isEmpty {
            data["measurables"] = measurables.map { ["label": $0.label, "value": $0.value] }
        }
        let contact = info.visibleContactItems
        if !contact.isEmpty {
            data["contact"] = contact.map { ["kind": $0.kind.rawValue, "label": $0.label, "value": $0.value] }
        }
    }

    private static func golfPayload(_ stats: RecruitingGolfStats) -> [String: Any] {
        var payload: [String: Any] = [
            "lead": stats.leadStats.map { ["label": $0.label, "value": $0.value] },
            "footnote": RecruitingGolfStats.footnote
        ]
        if stats.hasDetailed {
            payload["detailed"] = stats.detailedStats.map { ["label": $0.label, "value": $0.value] }
        }
        if !stats.recentRounds.isEmpty {
            payload["recentRounds"] = stats.recentRounds.map { round in
                [
                    "date": round.dateString,
                    "course": round.course,
                    "score": "\(round.score)",
                    "toPar": round.toParString
                ]
            }
        }
        return payload
    }
}

// MARK: - Clip label

extension VideoClip {
    /// Caption shown under a clip on the published page — pre-formatted here so
    /// the Cloud Function never needs to understand PlayResult, Club, or scoring.
    /// "Triple · vs Eagles · Mar 12" / "Birdie · Hole 14 · Jun 14" / "Driver · Jun 14".
    var recruitingLabel: String {
        let isGolf = (athlete?.sport ?? .baseball) == .golf
        var parts: [String] = []

        // Lead with the OUTCOME — it's the only part a coach scans for. On a golf
        // clip that's a birdie-or-better score, not the club: "Birdie" earns the
        // rewatch, "Driver" is trivia. Club stays as the fallback wherever there's
        // no outcome worth naming — a range clip, or a hole the athlete didn't
        // score under par.
        if let result = playResult?.type.displayName, !result.isEmpty {
            parts.append(result)
        } else if let golfOutcome {
            parts.append(golfOutcome)
        } else if let club {
            parts.append(club.displayName)
        }

        if let holeNumber {
            parts.append("Hole \(holeNumber)")
        } else if let opponent = gameOpponent, !opponent.isEmpty {
            // `gameOpponent` holds the COURSE on a golf round, so "vs" would read
            // as though the athlete played a match against Barton Creek.
            parts.append(isGolf ? opponent : "vs \(opponent)")
        }

        if let date = gameDate ?? practiceDate ?? createdAt {
            parts.append(DateFormatter.monthDay.string(from: date))
        }
        return parts.joined(separator: " · ")
    }

    /// "Birdie" / "Eagle" / "Hole-in-One" for a golf clip stamped with a scored
    /// hole. Reuses HoleScore.diffLabel so the page names a score exactly the way
    /// the scorecard does — but only for birdie-or-better. The picker doesn't
    /// restrict what the athlete can feature, and this caption is read by college
    /// coaches: a clip that happens to sit on a bogey hole is better labeled by
    /// its club than by "Double Bogey". Holes hang off Practice as well as Game,
    /// so a practice-round birdie labels the same as a tournament one.
    private var golfOutcome: String? {
        guard let holeNumber,
              let hole = (game?.holeScores ?? practice?.holeScores ?? [])
                  .first(where: { $0.holeNumber == holeNumber }),
              hole.isBirdieOrBetter
        else { return nil }
        return hole.diffLabel
    }
}
