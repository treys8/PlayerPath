//
//  RecruitingInfo.swift
//  PlayerPath
//
//  Athlete recruiting-profile bio, stored as a single JSON blob on
//  `Athlete.recruitingProfileJSON` (mirrors the `Game.scorecardData` precedent)
//  rather than ~20 individual synced columns. One field through the athlete
//  sync chain instead of twenty — avoids the per-field-whitelist drop bug
//  (the `holeNumber` data-loss class).
//

import Foundation

/// Recruiting bio for an athlete's video-first recruiting profile.
///
/// Every field is optional or defaulted and decoded with `decodeIfPresent`, so
/// older or newer blobs round-trip without throwing — the `FirestoreSeason`
/// lesson: a non-optional `Bool` with a default still traps synthesized
/// `init(from:)` when the key is absent from an older blob. `schemaVersion`
/// future-proofs the Phase 2 publish snapshot.
///
/// Golf intentionally stores nothing sport-specific here: the golf stat band is
/// derived live (handicap / scoring average / GIR…) at preview time so it never
/// disagrees with the in-app Stats screen.
// `nonisolated` so the Codable conformance can be used from JSONDecoder/Encoder's
// nonisolated generic context (this module is MainActor-by-default). Pure value
// type, so this is also correct for Sendability.
nonisolated struct RecruitingInfo: Codable, Equatable {
    /// Blob format version. Bump when adding fields that need migration logic.
    var schemaVersion: Int = 1

    // MARK: - Shared (all sports)
    var gradYear: Int?
    var heightInches: Int?
    var weightLbs: Int?
    var city: String?
    var state: String?
    var highSchool: String?
    var clubTeam: String?
    var bio: String?
    /// Firebase Storage download URL for the headshot — NOT a device-local path,
    /// so it renders on other devices once the blob syncs.
    var headshotCloudURL: String?

    // MARK: - Baseball / softball (video-first; opt-in self-entered measurables)
    var primaryPosition: String?
    var secondaryPosition: String?
    var bats: String?          // "L" / "R" / "S"
    var throwsHand: String?    // "L" / "R"
    /// Single opt-in for the whole self-entered measurables row. Clearly labeled
    /// athlete-entered in the UI — these are bio, not tracked stats.
    var showMeasurables: Bool = false
    var sixtyYardDash: Double?   // seconds
    var exitVelo: Double?        // mph
    var throwingVelo: Double?    // mph
    var pitchVelo: Double?       // mph

    // MARK: - PII (per-field opt-in; value + explicit Bool, default OFF)
    // Store the value AND an explicit flag rather than relying on presence:
    // presence/absence conflates "not entered" with "entered but kept private",
    // and the Phase 2 publish gate needs that distinction.
    var gpa: Double?
    var includeGPA: Bool = false
    var contactEmail: String?
    var includeContactEmail: Bool = false
    var contactPhone: String?
    var includeContactPhone: Bool = false

    // MARK: - Publish consent (Phase 2)

    /// When the account owner confirmed they're the athlete's parent/guardian (or
    /// are 13+) before the FIRST publish. Publishing makes a minor's photo — and
    /// any opted-in contact info — world-readable, and the app has no age gate, so
    /// this is the one place that confirmation is taken. Nil = never published.
    /// Lives in the blob (not a new `Athlete` column) so it syncs across the
    /// owner's devices with no new sync sites.
    var publishConsentAt: Date?

    /// The clips the athlete curated onto the published page, in page order
    /// (first = hero). Nil until the first publish.
    ///
    /// This is the *published* set, not a draft: without it the picker's
    /// selection lived only in view state, so relaunching the app re-seeded it to
    /// "newest 8 highlights" and the next "Update Published Profile" silently
    /// replaced a curated page. Stored in the blob for the same reason as
    /// `publishConsentAt` — it syncs across the owner's devices for free.
    var publishedClipIDs: [UUID]?

    /// The contact/academic kinds (`RecruitingStatItem.Kind` raw values — `gpa`,
    /// `email`, `phone`) that the last publish actually made public.
    ///
    /// Consent is taken ONCE, before the first publish, and `publishConsentAt` is
    /// then carried forward forever — so a republish that newly exposes a minor's
    /// phone number used to go out with no confirmation and no change summary.
    /// This records what has already been consented to, so the gate can re-arm for
    /// anything NEW rather than for everything or nothing.
    ///
    /// **Nil means "unknown baseline", not "nothing was public"** — a profile
    /// published before this field existed can't be diffed, and claiming a field is
    /// newly public there would be a guess. Nothing is re-prompted in that state;
    /// the next publish records the baseline and heals it. Same silent-when-unknown
    /// rule as P3.1's stale-highlight count.
    ///
    /// Publish-owned like `publishConsentAt` and `publishedClipIDs`, so it needs
    /// the same three protections: the nil-never-overwrites rule in
    /// `mergedRecruitingBlob`, a carry-forward line in the editor's
    /// `persistIfChanged`, and (already handled) the unknown-key sidecar so an
    /// older build doesn't destroy it on the first bio edit.
    var publishedContactKinds: [String]?

    /// Blob keys this build doesn't model, carried through untouched.
    ///
    /// The `recruiting` accessor re-encodes the WHOLE struct on every write, so
    /// without this any key added by a newer build is destroyed the first time an
    /// older build edits any field — see RecruitingBlobValue for the concrete
    /// data-loss case. Kept private: nothing should read these, they only need to
    /// survive the round trip.
    private var unknownKeys: [String: RecruitingBlobValue] = [:]

    init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case gradYear, heightInches, weightLbs, city, state, highSchool, clubTeam, bio, headshotCloudURL
        case primaryPosition, secondaryPosition, bats, throwsHand, showMeasurables
        case sixtyYardDash, exitVelo, throwingVelo, pitchVelo
        case gpa, includeGPA, contactEmail, includeContactEmail, contactPhone, includeContactPhone
        case publishConsentAt, publishedClipIDs, publishedContactKinds
    }

    /// Every key this build models. Anything in the stored blob that isn't here is
    /// captured into `unknownKeys` and written back out verbatim.
    private static let knownKeys: Set<String> = Set(
        [CodingKeys.schemaVersion, .gradYear, .heightInches, .weightLbs, .city, .state,
         .highSchool, .clubTeam, .bio, .headshotCloudURL, .primaryPosition,
         .secondaryPosition, .bats, .throwsHand, .showMeasurables, .sixtyYardDash,
         .exitVelo, .throwingVelo, .pitchVelo, .gpa, .includeGPA, .contactEmail,
         .includeContactEmail, .contactPhone, .includeContactPhone,
         .publishConsentAt, .publishedClipIDs, .publishedContactKinds].map(\.rawValue)
    )

    /// Decodes one key, degrading a bad VALUE to nil instead of throwing.
    ///
    /// `decodeIfPresent` alone only tolerates a missing key — a key that's present
    /// with the wrong type (a future build changing a field's shape, or one
    /// malformed UUID in `publishedClipIDs`) throws, and a throw here is not a
    /// small loss: the `recruiting` accessor catches it and hands back an EMPTY
    /// RecruitingInfo, which the editor's autosave then writes over the real blob.
    /// One bad field would silently erase the athlete's whole profile. Losing that
    /// single field instead is strictly better, and the unknown-key sidecar means
    /// cross-version blobs are now an expected input, not a freak event.
    private static func lenient<T: Decodable>(
        _ c: KeyedDecodingContainer<CodingKeys>, _ type: T.Type, _ key: CodingKeys
    ) -> T? {
        (try? c.decodeIfPresent(type, forKey: key)) ?? nil
    }

    // Custom decoder: no key can throw, so a blob written by an older or newer
    // build — missing keys, extra keys, or a changed value type — always decodes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = Self.lenient(c, Int.self, .schemaVersion) ?? 1
        gradYear = Self.lenient(c, Int.self, .gradYear)
        heightInches = Self.lenient(c, Int.self, .heightInches)
        weightLbs = Self.lenient(c, Int.self, .weightLbs)
        city = Self.lenient(c, String.self, .city)
        state = Self.lenient(c, String.self, .state)
        highSchool = Self.lenient(c, String.self, .highSchool)
        clubTeam = Self.lenient(c, String.self, .clubTeam)
        bio = Self.lenient(c, String.self, .bio)
        headshotCloudURL = Self.lenient(c, String.self, .headshotCloudURL)
        primaryPosition = Self.lenient(c, String.self, .primaryPosition)
        secondaryPosition = Self.lenient(c, String.self, .secondaryPosition)
        bats = Self.lenient(c, String.self, .bats)
        throwsHand = Self.lenient(c, String.self, .throwsHand)
        showMeasurables = Self.lenient(c, Bool.self, .showMeasurables) ?? false
        sixtyYardDash = Self.lenient(c, Double.self, .sixtyYardDash)
        exitVelo = Self.lenient(c, Double.self, .exitVelo)
        throwingVelo = Self.lenient(c, Double.self, .throwingVelo)
        pitchVelo = Self.lenient(c, Double.self, .pitchVelo)
        gpa = Self.lenient(c, Double.self, .gpa)
        includeGPA = Self.lenient(c, Bool.self, .includeGPA) ?? false
        contactEmail = Self.lenient(c, String.self, .contactEmail)
        includeContactEmail = Self.lenient(c, Bool.self, .includeContactEmail) ?? false
        contactPhone = Self.lenient(c, String.self, .contactPhone)
        includeContactPhone = Self.lenient(c, Bool.self, .includeContactPhone) ?? false
        publishConsentAt = Self.lenient(c, Date.self, .publishConsentAt)
        publishedClipIDs = Self.lenient(c, [UUID].self, .publishedClipIDs)
        publishedContactKinds = Self.lenient(c, [String].self, .publishedContactKinds)

        // Anything this build doesn't model. Best-effort: a blob that somehow
        // isn't a plain JSON object must not make the whole bio undecodable —
        // losing the entire profile to preserve a stray key would be a worse bug
        // than the one this fixes.
        if let all = try? decoder.singleValueContainer()
            .decode([String: RecruitingBlobValue].self) {
            unknownKeys = all.filter { !Self.knownKeys.contains($0.key) }
        }
    }

    // Hand-written to match: Encodable synthesis would silently drop `unknownKeys`
    // (it's a stored property, so it would actually be encoded under the literal
    // key "unknownKeys" — a nested object that then re-decodes as an unknown key
    // and grows every save). Known keys use encodeIfPresent so the emitted shape
    // is byte-identical to what synthesis produced before this change.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(gradYear, forKey: .gradYear)
        try c.encodeIfPresent(heightInches, forKey: .heightInches)
        try c.encodeIfPresent(weightLbs, forKey: .weightLbs)
        try c.encodeIfPresent(city, forKey: .city)
        try c.encodeIfPresent(state, forKey: .state)
        try c.encodeIfPresent(highSchool, forKey: .highSchool)
        try c.encodeIfPresent(clubTeam, forKey: .clubTeam)
        try c.encodeIfPresent(bio, forKey: .bio)
        try c.encodeIfPresent(headshotCloudURL, forKey: .headshotCloudURL)
        try c.encodeIfPresent(primaryPosition, forKey: .primaryPosition)
        try c.encodeIfPresent(secondaryPosition, forKey: .secondaryPosition)
        try c.encodeIfPresent(bats, forKey: .bats)
        try c.encodeIfPresent(throwsHand, forKey: .throwsHand)
        try c.encode(showMeasurables, forKey: .showMeasurables)
        try c.encodeIfPresent(sixtyYardDash, forKey: .sixtyYardDash)
        try c.encodeIfPresent(exitVelo, forKey: .exitVelo)
        try c.encodeIfPresent(throwingVelo, forKey: .throwingVelo)
        try c.encodeIfPresent(pitchVelo, forKey: .pitchVelo)
        try c.encodeIfPresent(gpa, forKey: .gpa)
        try c.encode(includeGPA, forKey: .includeGPA)
        try c.encodeIfPresent(contactEmail, forKey: .contactEmail)
        try c.encode(includeContactEmail, forKey: .includeContactEmail)
        try c.encodeIfPresent(contactPhone, forKey: .contactPhone)
        try c.encode(includeContactPhone, forKey: .includeContactPhone)
        try c.encodeIfPresent(publishConsentAt, forKey: .publishConsentAt)
        try c.encodeIfPresent(publishedClipIDs, forKey: .publishedClipIDs)
        try c.encodeIfPresent(publishedContactKinds, forKey: .publishedContactKinds)

        // Same encoder, second keyed container: JSONEncoder merges both into one
        // object. A stale key can never shadow a real one — knownKeys was filtered
        // out on decode.
        var dynamic = encoder.container(keyedBy: RecruitingBlobKey.self)
        for (key, value) in unknownKeys {
            guard let codingKey = RecruitingBlobKey(stringValue: key) else { continue }
            try dynamic.encode(value, forKey: codingKey)
        }
    }
}

// MARK: - Display helpers (shared by editor, preview, and publish snapshot)
//
// These build every string the profile renders. The in-app preview
// (RecruitingProfileView) and the published web page (via
// RecruitingProfileService) both read them, so a coach's page can never word
// something differently from what the athlete previewed.

extension RecruitingInfo {
    /// "Class of 2027 · Baseball · SS / 2B, OF" — positions are baseball/softball only.
    ///
    /// The sport is named explicitly because nothing else on the page says it:
    /// "SS / 2B" reads as baseball to a baseball coach and as softball to a
    /// softball coach, and a golf profile carries no positions at all, so it had
    /// no sport signal whatsoever. This string is also the page's `og:title`
    /// suffix, so naming the sport here is what makes a shared link legible in an
    /// unfurl — and it stays a single source, so the in-app preview and the
    /// published page cannot word it differently.
    func subline(sport: Sport) -> String? {
        var parts: [String] = []
        if let gradYear { parts.append("Class of \(gradYear)") }
        parts.append(sport.displayName)
        if sport != .golf, let positionLine { parts.append(positionLine) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "SS" / "SS / 2B, OF". Secondary positions ride along with the primary
    /// rather than being dropped: a kid who can cover three spots is worth more
    /// to a college roster than one who can't, and that's the whole reason the
    /// editor asks for them.
    var positionLine: String? {
        let primary = Self.normalizedPositions(primaryPosition)
        let secondary = Self.normalizedPositions(secondaryPosition)
        switch (primary, secondary) {
        case let (primary?, secondary?): return "\(primary) / \(secondary)"
        case let (primary?, nil):        return primary
        case let (nil, secondary?):      return secondary
        default:                         return nil
        }
    }

    /// Tidies a free-text position field into `"2B, OF"`. The editor takes both
    /// fields as plain text, so `"2B ,  of "` is a normal thing to receive and
    /// would otherwise publish exactly as typed. Nil when nothing survives.
    private static func normalizedPositions(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let tokens = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return tokens.isEmpty ? nil : tokens.joined(separator: ", ")
    }

    /// "6'1\" · 180 lbs · B/T R/R · Austin, TX"
    func physicalLine(isGolf: Bool) -> String? {
        var parts: [String] = []
        if let heightFormatted { parts.append(heightFormatted) }
        if let weightLbs { parts.append("\(weightLbs) lbs") }
        if !isGolf, let bats, let throwsHand, !bats.isEmpty, !throwsHand.isEmpty {
            parts.append("B/T \(bats)/\(throwsHand)")
        }
        if let locationLine { parts.append(locationLine) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Austin High · Texas Thunder 16U"
    var schoolLine: String? {
        let parts = [highSchool, clubTeam].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Self-entered measurables, in display order. Empty unless `showMeasurables`
    /// is on — the opt-in is enforced here so no caller can leak the row.
    var measurableItems: [RecruitingStatItem] {
        guard showMeasurables else { return [] }
        var items: [RecruitingStatItem] = []
        if let sixtyYardDash {
            items.append(.init(kind: .sixty, label: "60 Yard", value: String(format: "%.2f", sixtyYardDash) + "s"))
        }
        if let exitVelo {
            items.append(.init(kind: .exitVelo, label: "Exit Velo", value: "\(Int(exitVelo.rounded())) mph"))
        }
        if let throwingVelo {
            items.append(.init(kind: .throwVelo, label: "Throw Velo", value: "\(Int(throwingVelo.rounded())) mph"))
        }
        if let pitchVelo {
            items.append(.init(kind: .pitchVelo, label: "Pitch Velo", value: "\(Int(pitchVelo.rounded())) mph"))
        }
        return items
    }

    /// Contact/academic rows the athlete opted into publishing. A value that was
    /// entered but left private must never appear here — presence alone is not
    /// consent, which is why each field carries an explicit `include*` flag.
    var visibleContactItems: [RecruitingStatItem] {
        var items: [RecruitingStatItem] = []
        if includeGPA, let gpa {
            items.append(.init(kind: .gpa, label: "GPA", value: String(format: "%.2f", gpa)))
        }
        if includeContactEmail, let contactEmail, !contactEmail.isEmpty {
            items.append(.init(kind: .email, label: "Email", value: contactEmail))
        }
        if includeContactPhone, let contactPhone, !contactPhone.isEmpty {
            items.append(.init(kind: .phone, label: "Phone", value: contactPhone))
        }
        return items
    }

    /// Contact/academic kinds that are opted in NOW but weren't on the last
    /// published page — i.e. what a republish would newly expose.
    ///
    /// Empty when `publishedContactKinds` is nil: unknown baseline, so nothing can
    /// honestly be called new (see that property). Also empty on a first publish,
    /// where the blanket consent gate covers it instead.
    var newlyPublicContactKinds: [RecruitingStatItem.Kind] {
        guard let publishedContactKinds else { return [] }
        let alreadyPublic = Set(publishedContactKinds)
        return visibleContactItems.map(\.kind).filter { !alreadyPublic.contains($0.rawValue) }
    }

    /// True when the published page carries a way for a coach to actually reply.
    ///
    /// Deliberately NOT `!visibleContactItems.isEmpty`: that array also holds GPA,
    /// so a page showing a 3.8 and nothing else would count as reachable while
    /// giving a coach who scanned a QR code at a showcase table no way to contact
    /// anyone. Only email and phone are reply channels — and each still has to be
    /// opted in, because a value entered but kept private is not a public channel.
    ///
    /// ShareLink and the coach mailto both leave a thread the coach can reply
    /// into, so this only matters for the channels that don't: a scanned QR code,
    /// a link in a social bio, and any forwarded link.
    var hasPublicReplyChannel: Bool {
        (includeContactEmail && contactEmail?.isEmpty == false)
            || (includeContactPhone && contactPhone?.isEmpty == false)
    }

    /// "Austin, TX" — nil when neither city nor state is set.
    var locationLine: String? {
        let parts = [city, state].compactMap { value -> String? in
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// `73` → `6'1"`. Nil when height isn't set.
    var heightFormatted: String? {
        guard let heightInches, heightInches > 0 else { return nil }
        return "\(heightInches / 12)'\(heightInches % 12)\""
    }

    /// Count of completed non-PII bio fields — used as a coarse "how filled in is
    /// this profile" signal for analytics (`fields_completed`).
    var filledFieldCount: Int {
        var n = 0
        if gradYear != nil { n += 1 }
        if heightInches != nil { n += 1 }
        if weightLbs != nil { n += 1 }
        if locationLine != nil { n += 1 }
        if highSchool?.isEmpty == false { n += 1 }
        if clubTeam?.isEmpty == false { n += 1 }
        if bio?.isEmpty == false { n += 1 }
        if headshotCloudURL?.isEmpty == false { n += 1 }
        if primaryPosition?.isEmpty == false { n += 1 }
        if secondaryPosition?.isEmpty == false { n += 1 }
        if bats?.isEmpty == false { n += 1 }
        if throwsHand?.isEmpty == false { n += 1 }
        if sixtyYardDash != nil { n += 1 }
        if exitVelo != nil { n += 1 }
        if throwingVelo != nil { n += 1 }
        if pitchVelo != nil { n += 1 }
        return n
    }
}

// MARK: - Athlete accessor

extension Athlete {
    /// Decoded recruiting bio for this athlete. Reads return an empty
    /// `RecruitingInfo` when the blob is nil/empty/malformed (never crashes).
    /// Writes re-encode the blob and set `needsSync = true` only — `version` is
    /// bumped later in `SyncCoordinator.uploadLocalAthletes`, NOT here (matches
    /// the rest of the sync chain; see `EditAthleteView`).
    var recruiting: RecruitingInfo {
        get {
            guard let json = recruitingProfileJSON,
                  !json.isEmpty,
                  let data = json.data(using: .utf8),
                  let info = try? JSONDecoder().decode(RecruitingInfo.self, from: data)
            else { return RecruitingInfo() }
            return info
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else { return }
            recruitingProfileJSON = json
            needsSync = true
        }
    }

    /// True once the athlete has saved any recruiting bio.
    var hasRecruitingProfile: Bool {
        recruitingProfileJSON?.isEmpty == false
    }

    /// Reconciles two versions of the recruiting blob without letting the
    /// publish-owned fields regress to nil.
    ///
    /// The blob otherwise syncs as ONE opaque last-write-wins string, and two of
    /// its fields aren't owned by the bio editor at all: `publishConsentAt` and
    /// `publishedClipIDs` are written only by the publish path. So a device that
    /// has an offline bio edit and has never seen a publish uploads a blob with
    /// both keys nil and erases them for the whole account — after which the
    /// publish screen re-seeds the curation to "newest 8" and one tap on
    /// "Update Published Profile" silently replaces the hero clip and ordering on
    /// the page a college coach is looking at.
    ///
    /// Neither field is ever legitimately cleared, so "nil never overwrites
    /// non-nil" is the whole rule. When both sides have a value, normal
    /// last-write-wins applies and `incoming` takes it.
    ///
    /// A nil `incoming` means "this side has no blob", never "clear the bio" —
    /// nothing in the app sets `recruitingProfileJSON` back to nil.
    static func mergedRecruitingBlob(incoming: String?, existing: String?) -> String? {
        guard let incoming, !incoming.isEmpty else { return existing }
        guard let existing, !existing.isEmpty else { return incoming }

        let decoder = JSONDecoder()
        guard let incomingData = incoming.data(using: .utf8),
              let existingData = existing.data(using: .utf8),
              var merged = try? decoder.decode(RecruitingInfo.self, from: incomingData),
              let local = try? decoder.decode(RecruitingInfo.self, from: existingData)
        else {
            // Undecodable on either side — fall back to the plain swap rather than
            // inventing a value.
            return incoming
        }
        if merged.publishConsentAt == nil { merged.publishConsentAt = local.publishConsentAt }
        if merged.publishedClipIDs == nil { merged.publishedClipIDs = local.publishedClipIDs }
        // Losing this would silently DISARM the re-consent gate: a nil baseline
        // reads as "unknown", so every already-public field would look consented
        // and a newly-shared phone number would publish with no re-prompt.
        if merged.publishedContactKinds == nil { merged.publishedContactKinds = local.publishedContactKinds }

        guard let data = try? JSONEncoder().encode(merged),
              let json = String(data: data, encoding: .utf8) else { return incoming }
        return json
    }
}
