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

    init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case gradYear, heightInches, weightLbs, city, state, highSchool, clubTeam, bio, headshotCloudURL
        case primaryPosition, secondaryPosition, bats, throwsHand, showMeasurables
        case sixtyYardDash, exitVelo, throwingVelo, pitchVelo
        case gpa, includeGPA, contactEmail, includeContactEmail, contactPhone, includeContactPhone
        case publishConsentAt
    }

    // Custom decoder: every key via `decodeIfPresent` so a blob written by an
    // older or newer build (missing/extra keys) never throws. Encoding stays
    // synthesized (Encodable synthesis is independent of a custom init(from:)).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        gradYear = try c.decodeIfPresent(Int.self, forKey: .gradYear)
        heightInches = try c.decodeIfPresent(Int.self, forKey: .heightInches)
        weightLbs = try c.decodeIfPresent(Int.self, forKey: .weightLbs)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        highSchool = try c.decodeIfPresent(String.self, forKey: .highSchool)
        clubTeam = try c.decodeIfPresent(String.self, forKey: .clubTeam)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        headshotCloudURL = try c.decodeIfPresent(String.self, forKey: .headshotCloudURL)
        primaryPosition = try c.decodeIfPresent(String.self, forKey: .primaryPosition)
        secondaryPosition = try c.decodeIfPresent(String.self, forKey: .secondaryPosition)
        bats = try c.decodeIfPresent(String.self, forKey: .bats)
        throwsHand = try c.decodeIfPresent(String.self, forKey: .throwsHand)
        showMeasurables = try c.decodeIfPresent(Bool.self, forKey: .showMeasurables) ?? false
        sixtyYardDash = try c.decodeIfPresent(Double.self, forKey: .sixtyYardDash)
        exitVelo = try c.decodeIfPresent(Double.self, forKey: .exitVelo)
        throwingVelo = try c.decodeIfPresent(Double.self, forKey: .throwingVelo)
        pitchVelo = try c.decodeIfPresent(Double.self, forKey: .pitchVelo)
        gpa = try c.decodeIfPresent(Double.self, forKey: .gpa)
        includeGPA = try c.decodeIfPresent(Bool.self, forKey: .includeGPA) ?? false
        contactEmail = try c.decodeIfPresent(String.self, forKey: .contactEmail)
        includeContactEmail = try c.decodeIfPresent(Bool.self, forKey: .includeContactEmail) ?? false
        contactPhone = try c.decodeIfPresent(String.self, forKey: .contactPhone)
        includeContactPhone = try c.decodeIfPresent(Bool.self, forKey: .includeContactPhone) ?? false
        publishConsentAt = try c.decodeIfPresent(Date.self, forKey: .publishConsentAt)
    }
}

// MARK: - Display helpers (shared by editor, preview, and publish snapshot)
//
// These build every string the profile renders. The in-app preview
// (RecruitingProfileView) and the published web page (via
// RecruitingProfileService) both read them, so a coach's page can never word
// something differently from what the athlete previewed.

extension RecruitingInfo {
    /// "Class of 2027 · SS / 2B, OF" — positions are baseball/softball only.
    func subline(isGolf: Bool) -> String? {
        var parts: [String] = []
        if let gradYear { parts.append("Class of \(gradYear)") }
        if !isGolf, let positionLine { parts.append(positionLine) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "SS" / "SS / 2B, OF". Secondary positions ride along with the primary
    /// rather than being dropped: a kid who can cover three spots is worth more
    /// to a college roster than one who can't, and that's the whole reason the
    /// editor asks for them.
    var positionLine: String? {
        let primary = primaryPosition?.trimmingCharacters(in: .whitespaces)
        let secondary = secondaryPosition?.trimmingCharacters(in: .whitespaces)
        switch (primary?.isEmpty == false ? primary : nil,
                secondary?.isEmpty == false ? secondary : nil) {
        case let (primary?, secondary?): return "\(primary) / \(secondary)"
        case let (primary?, nil):        return primary
        case let (nil, secondary?):      return secondary
        default:                         return nil
        }
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
}
