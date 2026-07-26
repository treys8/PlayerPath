//
//  RecruitingBlobValue.swift
//  PlayerPath
//
//  A minimal JSON value, used only to carry recruiting-blob keys that the running
//  build doesn't model.
//
//  WHY. `Athlete.recruitingProfileJSON` is one JSON blob, and the `recruiting`
//  accessor decodes it, hands out a struct, and re-encodes the whole thing on
//  every write. Any key the running build doesn't know about is therefore
//  DESTROYED the first time that build touches any field — and the blob has
//  already shipped in three shapes (neither publish key / publishConsentAt only /
//  both). A device still on an older App Store build that edits a bio would
//  permanently drop the newer build's `publishedClipIDs`, silently resetting the
//  athlete's curated page to "newest 8". Round-tripping unknown keys through this
//  type makes the blob forward-compatible instead.
//

import Foundation

/// One JSON value of unknown shape. Deliberately not a general-purpose AnyCodable:
/// it exists to survive a decode/encode round trip unchanged, nothing more.
nonisolated enum RecruitingBlobValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([RecruitingBlobValue])
    case object([String: RecruitingBlobValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Int.self) {
            // Int before Double: JSON has one number type, and decoding 2026 as a
            // Double would re-encode it as 2026 anyway, but an Int keeps integral
            // values from acquiring a ".0" that changes the blob's bytes.
            self = .int(v)
        } else if let v = try? c.decode(Double.self) {
            self = .double(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([RecruitingBlobValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: RecruitingBlobValue].self) {
            self = .object(v)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

/// Coding key built at runtime, so unknown blob keys can be written back out under
/// their original names.
nonisolated struct RecruitingBlobKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    /// Blob keys are always strings — an integer-keyed container never occurs here.
    init?(intValue: Int) { return nil }
}
