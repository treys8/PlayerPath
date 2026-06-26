//
//  ReelExportOptionsView.swift
//  PlayerPath
//
//  Compact "Customize for social" sheet for a reel: toggle the name overlay, edit the
//  caption, pick aspect (Original / 9:16), and (for 9:16) Fit vs Fill. Hands a built
//  ReelExportOptions back to GenerateReelView on Apply, which re-stitches a variant.
//  Standalone sheet — owns its own NavigationStack for the toolbar buttons.
//

import SwiftUI

struct ReelExportOptionsView: View {
    /// Athlete name used for the name line (nil ⇒ no name toggle shown).
    let athleteName: String?
    /// The currently-applied options, used to seed the controls.
    let initial: ReelExportOptions
    /// Called with the freshly-built options when the user taps Apply.
    let onApply: (ReelExportOptions) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var includeName: Bool
    @State private var caption: String
    @State private var aspect: ReelExportOptions.Aspect
    @State private var cropMode: ReelExportOptions.CropMode

    init(athleteName: String?, initial: ReelExportOptions, onApply: @escaping (ReelExportOptions) -> Void) {
        self.athleteName = athleteName
        self.initial = initial
        self.onApply = onApply
        _includeName = State(initialValue: initial.resolvedName != nil)
        _caption = State(initialValue: initial.captionText ?? "")
        _aspect = State(initialValue: initial.aspect)
        _cropMode = State(initialValue: initial.cropMode)
    }

    /// The options the controls currently describe.
    private var builtOptions: ReelExportOptions {
        ReelExportOptions(
            nameText: (includeName ? athleteName : nil),
            captionText: caption,
            aspect: aspect,
            cropMode: cropMode
        )
    }

    private var previewText: String {
        [builtOptions.resolvedName, builtOptions.resolvedCaption]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if athleteName != nil {
                        Toggle("Show athlete name", isOn: $includeName)
                    }
                    TextField("Caption (e.g. vs Tigers · Jun 8)", text: $caption)
                } header: {
                    Text("Overlay")
                } footer: {
                    Text("Baked into the video. No PlayerPath logo is added.")
                }

                Section("Format") {
                    Picker("Aspect", selection: $aspect) {
                        Text("Original").tag(ReelExportOptions.Aspect.source)
                        Text("Vertical 9:16").tag(ReelExportOptions.Aspect.vertical9x16)
                    }
                    if aspect == .vertical9x16 {
                        Picker("Frame", selection: $cropMode) {
                            Text("Fit (black bars)").tag(ReelExportOptions.CropMode.letterbox)
                            Text("Fill (crop edges)").tag(ReelExportOptions.CropMode.centerCrop)
                        }
                    }
                }

                if !previewText.isEmpty {
                    Section("Preview") {
                        HStack(spacing: 8) {
                            Image(systemName: "textformat")
                                .foregroundStyle(.secondary)
                            Text(previewText)
                                .font(.labelMedium)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("Customize for Social")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(builtOptions)
                        dismiss()
                    }
                }
            }
        }
    }
}
