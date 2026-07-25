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

// MARK: - Stat chip color

extension RecruitingStatItem.Kind {
    /// Chip color for a stat item. Lives here (not on the model) so
    /// `RecruitingStatItem` stays SwiftUI-free, and is defined once so the golf
    /// band and the measurables grid can't tint the same kind differently.
    /// Deliberately exhaustive — a new kind must choose a color, not inherit one.
    var chipColor: Color {
        switch self {
        case .handicap: return Theme.golfAccent
        case .roundAvg, .fairways, .putts: return .brandNavy
        case .best, .gir: return .green
        case .rounds: return .secondary
        case .scrambling: return .mint
        case .sixty, .exitVelo, .throwVelo, .pitchVelo: return .brandNavy
        case .gpa, .email, .phone: return .secondary
        }
    }
}

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

/// Horizontally-scrolling strip of the athlete's highlight clips. Reuses the
/// cached `VideoThumbnailView`.
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
        return Array(
            all
                .filter { $0.isHighlight }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                .prefix(limit)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Highlights")
                .font(.headingMedium)
            if clips.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(clips) { clip in
                            VideoThumbnailView(
                                clip: clip,
                                size: CGSize(width: 200, height: 112),
                                cornerRadius: 12,
                                showPlayResult: true,
                                showHighlight: false,
                                showNote: false,
                                showContext: true,
                                showDuration: true
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "film.stack")
                .foregroundStyle(.secondary)
            Text("Flag your best clips as highlights to feature them here.")
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

    init(_ title: String,
         prompt: String = "—",
         text: Binding<String>,
         keyboard: UIKeyboardType = .default,
         autocapitalization: TextInputAutocapitalization = .words,
         autocorrect: Bool = true) {
        self.title = title
        self.prompt = prompt
        self._text = text
        self.keyboard = keyboard
        self.autocapitalization = autocapitalization
        self.autocorrect = autocorrect
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
    @State private var text: String = ""

    init(_ title: String, unit: String? = nil, value: Binding<Double?>, isInteger: Bool = false) {
        self.title = title
        self.unit = unit
        self._value = value
        self.isInteger = isInteger
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(isInteger ? .numberPad : .decimalPad)
                .frame(maxWidth: 90)
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
