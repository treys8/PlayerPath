//
//  RecruitingProfileComponents.swift
//  PlayerPath
//
//  Shared building blocks for the recruiting-profile editor + preview:
//  headshot image, highlight-clip strip, a numeric text field, and the
//  headshot downscale helper.
//

import SwiftUI
import UIKit

// MARK: - Headshot image

/// Circular headshot loaded from a Firebase Storage download URL (tokenized, so
/// it loads without a public-read rule). Falls back to a person placeholder.
struct RecruitingHeadshotImage: View {
    let url: String?
    var size: CGFloat = 96
    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ZStack { placeholder; ProgressView() }
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ppAccent.opacity(0.25), lineWidth: 1))
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Color.backgroundSecondary)
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .padding(size * 0.1)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Highlight strip

/// The "Game Film" section as the published page lays it out (`videoSection` in
/// recruitingProfile.ts): a provenance note, a full-width hero, then a two-column
/// grid, each clip captioned with the SAME `recruitingLabel` publish ships. Was a
/// horizontal strip with the app's generic context badge, which worded clips
/// differently from the page and dropped the year the page's date range carries.
///
/// Shows the CURATED set when one is supplied — the preview claims to be what a
/// college coach will see, so it has to render the clips that are actually on the
/// page, in the athlete's order, not the newest ones.
struct RecruitingHighlightStrip: View {
    let athlete: Athlete
    /// Clip IDs in published/page order (first = hero). Nil or empty falls back to
    /// newest-first highlights, which is exactly what the picker defaults to — so a
    /// profile that has never been published previews correctly either way.
    var curatedClipIDs: [UUID]?
    var limit: Int = 8

    private var clips: [VideoClip] {
        let all = athlete.videoClips ?? []
        if let curatedClipIDs, !curatedClipIDs.isEmpty {
            // compactMap over the ID list, not a filter over the clips: the stored
            // order IS the page order, and a clip deleted since publishing just drops.
            return curatedClipIDs.compactMap { id in all.first { $0.id == id } }
        }
        // `hasPublishableUpload`, not just "is a highlight": a clip still uploading has
        // nothing in Storage to sign, so publish drops it (the picker and
        // RecruitingProfileService.publish both filter on exactly this). Filtering
        // loosely here made the never-published preview — the one screen that claims
        // to be what a college coach will see — promise film the page can't carry.
        return Array(
            athlete.recruitingHighlights
                .filter(\.hasPublishableUpload)
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                .prefix(limit)
        )
    }

    /// Highlights that are flagged but not yet in Storage — i.e. the strip is empty
    /// because uploads are pending, not because nothing has been flagged.
    private var hasPendingHighlights: Bool {
        athlete.recruitingHighlights.contains { !$0.hasPublishableUpload }
    }

    /// The clip open in the full-screen player — the preview is where an athlete
    /// checks they picked the right moment, so the film has to actually play.
    @State private var playingClip: VideoClip?

    var body: some View {
        // Read once per render: `clips` walks `recruitingHighlights`, which on a
        // golf athlete runs a SwiftData fetch for the birdie-reel union.
        let clips = self.clips
        VStack(alignment: .leading, spacing: 8) {
            Text("Game Film")
                .font(.headingMedium)
            if clips.isEmpty {
                emptyState
            } else {
                let tiles = clips.map { Tile(clip: $0, caption: Self.caption(for: $0)) }
                Text(filmNote(tiles.map(\.clip)))
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
                if let hero = tiles.first {
                    tile(hero)
                }
                if tiles.count > 1 {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)],
                              alignment: .leading, spacing: 12) {
                        ForEach(tiles.dropFirst()) { tile($0) }
                    }
                }
            }
        }
        .fullScreenCover(item: $playingClip) { clip in
            VideoPlayerView(clip: clip)
        }
    }

    /// A clip plus its caption, built once per render — `recruitingLabel` walks a
    /// golf clip's holes, so it shouldn't run inside the grid's cell closure.
    private struct Tile: Identifiable {
        let clip: VideoClip
        let caption: String
        var id: UUID { clip.id }
    }

    private func tile(_ tile: Tile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                playingClip = tile.clip
            } label: {
                VideoThumbnailView(
                    clip: tile.clip,
                    size: CGSize(width: 320, height: 180),
                    cornerRadius: 12,
                    showPlayResult: false,
                    showHighlight: false,
                    showNote: false,
                    showContext: false,
                    showDuration: false,
                    fillsContainer: true
                )
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 4)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play clip")
            if !tile.caption.isEmpty {
                Text(tile.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    /// "1 clip · 0:03 · tagged in PlayerPath · Jul 2026" — the page's film note.
    private func filmNote(_ clips: [VideoClip]) -> String {
        let runtime = clips.reduce(0) { $0 + ($1.duration ?? 0) }
        return [
            "\(clips.count) clip\(clips.count == 1 ? "" : "s")",
            runtime > 0 ? Self.clockDuration(runtime) : "",
            "tagged in PlayerPath",
            RecruitingProfileService.filmDateRange(clips.compactMap(\.recruitingDate)) ?? ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    /// The page's `clipCaption`: label plus runtime.
    private static func caption(for clip: VideoClip) -> String {
        let runtime = (clip.duration ?? 0) > 0 ? clockDuration(clip.duration ?? 0) : ""
        return [clip.recruitingLabel, runtime].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Mirrors `clockDuration` in recruitingProfile.ts: "0:03", "12:40", "1:02:05".
    private static func clockDuration(_ totalSeconds: Double) -> String {
        let whole = max(0, Int(totalSeconds.rounded()))
        let hours = whole / 3600, minutes = (whole % 3600) / 60, seconds = whole % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "film.stack")
                .foregroundStyle(.secondary)
            // Telling someone who just flagged eight clips to go flag some clips is
            // the wrong-copy class of defect, so name the real reason. Matches the
            // wording RecruitingPublishView.clipsSection uses for the same state.
            Text(hasPendingHighlights
                 ? "Your highlights are still uploading — they'll appear here once they finish."
                 : "Flag your best clips as highlights to feature them here.")
                .font(.bodySmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

// MARK: - Labelled text field

/// A labelled, trailing-aligned text field — the text counterpart to
/// `RecruitingNumberField`, and laid out to match it and the Form's `Picker` rows.
///
/// A bare `TextField("City", …)` shows its title only while empty, so a filled-in
/// editor became a column of unlabelled values ("Starkville", "MS", "P", "CF")
/// with no way to tell which field was which. The label is always visible here.
struct RecruitingTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let autocapitalization: TextInputAutocapitalization
    let autocorrect: Bool
    /// False flags the value (see RecruitingInputRange) — a warning, not a block.
    let isValid: Bool

    init(_ title: String,
         prompt: String = "—",
         text: Binding<String>,
         keyboard: UIKeyboardType = .default,
         autocapitalization: TextInputAutocapitalization = .words,
         autocorrect: Bool = true,
         isValid: Bool = true) {
        self.title = title
        self.prompt = prompt
        self._text = text
        self.keyboard = keyboard
        self.autocapitalization = autocapitalization
        self.autocorrect = autocorrect
        self.isValid = isValid
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(prompt, text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(!autocorrect)
                .modifier(RecruitingFlagged(isFlagged: !isValid))
        }
    }
}

// MARK: - Sanity ranges

/// Plausible bounds for self-entered numbers. Out-of-range values are FLAGGED,
/// never blocked — a real outlier (a 105 mph arm) must still publish — but a GPA
/// of 38 or a 68.9 sixty is almost always a typo, and it goes out to coaches
/// exactly as typed. One table so each field and its section footer agree.
enum RecruitingInputRange {
    static let gpa: ClosedRange<Double> = 0...5
    static let sixty: ClosedRange<Double> = 5.5...12
    static let exitVelo: ClosedRange<Double> = 40...125
    static let throwVelo: ClosedRange<Double> = 40...110
    static let pitchVelo: ClosedRange<Double> = 40...110
    static let weight: ClosedRange<Double> = 60...350

    static func isFlagged(_ value: Double?, _ range: ClosedRange<Double>) -> Bool {
        guard let value else { return false }
        return !range.contains(value)
    }

    static let flaggedNote = "Double-check the highlighted values — coaches see exactly what you enter."
}

/// Warning glyph + tint for a field whose value looks wrong.
private struct RecruitingFlagged: ViewModifier {
    let isFlagged: Bool

    func body(content: Content) -> some View {
        HStack(spacing: 4) {
            if isFlagged {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .accessibilityLabel("Check this value")
            }
            content.foregroundStyle(isFlagged ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(.primary))
        }
    }
}

// MARK: - Numeric field

/// A trailing-aligned text field for an optional numeric model value. Holds the
/// raw string locally so partial input (e.g. "88." while typing a decimal) isn't
/// clobbered by re-parsing; commits the parsed value on every edit.
struct RecruitingNumberField: View {
    let title: String
    let unit: String?
    @Binding var value: Double?
    let isInteger: Bool
    /// Plausible bounds; a value outside them is flagged, never rejected.
    let validRange: ClosedRange<Double>?
    @State private var text: String = ""

    init(_ title: String, unit: String? = nil, value: Binding<Double?>, isInteger: Bool = false,
         validRange: ClosedRange<Double>? = nil) {
        self.title = title
        self.unit = unit
        self._value = value
        self.isInteger = isInteger
        self.validRange = validRange
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(isInteger ? .numberPad : .decimalPad)
                .frame(maxWidth: 90)
                .modifier(RecruitingFlagged(isFlagged: validRange.map { RecruitingInputRange.isFlagged(value, $0) } ?? false))
                .onChange(of: text) { _, newValue in
                    if newValue.isEmpty {
                        value = nil
                    } else if let parsed = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                        // Normalize comma decimals so a `,`-locale decimalPad still parses.
                        value = isInteger ? parsed.rounded() : parsed
                    }
                }
            if let unit {
                Text(unit)
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if let value {
                text = isInteger ? String(Int(value)) : trimmed(value)
            }
        }
    }

    private func trimmed(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }
}

// MARK: - Headshot downscale

extension UIImage {
    /// Downscaled JPEG for a recruiting headshot — caps the longest edge and
    /// re-encodes so the upload (and the eventual public-page egress) stays small.
    /// `nonisolated` so the editor can run the redraw/encode off the main actor
    /// (UIImage is Sendable and UIGraphicsImageRenderer is safe off-main).
    nonisolated func recruitingHeadshotData(maxDimension: CGFloat = 1024, quality: CGFloat = 0.8) -> Data? {
        let longest = max(size.width, size.height)
        let factor = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: size.width * factor, height: size.height * factor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
