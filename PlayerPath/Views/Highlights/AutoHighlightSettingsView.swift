//
//  AutoHighlightSettingsView.swift
//  PlayerPath
//
//  Settings view for configuring automatic highlight rules.
//

import SwiftUI
import SwiftData

// MARK: - Auto-Highlight Settings View

struct AutoHighlightSettingsView: View {
    let athlete: Athlete
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var settings = AutoHighlightSettings.shared

    @State private var isScanningLibrary = false
    @State private var scanResult: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Auto-Highlight Enabled", isOn: $settings.enabled)
                        .tint(.yellow)
                } footer: {
                    Text("When enabled, clips are automatically marked as highlights based on their play result when saved.")
                }

                if settings.enabled {
                    Section("Batting") {
                        Toggle("Home Run", isOn: $settings.includeHomeRuns)
                        Toggle("Triple",   isOn: $settings.includeTriples)
                        Toggle("Double",   isOn: $settings.includeDoubles)
                        Toggle("Single",   isOn: $settings.includeSingles)
                    }

                    Section("Pitching") {
                        Toggle("Strikeout",  isOn: $settings.includePitcherStrikeouts)
                        Toggle("Ground Out", isOn: $settings.includePitcherGroundOuts)
                        Toggle("Fly Out",    isOn: $settings.includePitcherFlyOuts)
                    }
                }

                Section {
                    Button {
                        Task { await scanLibrary() }
                    } label: {
                        HStack {
                            Label("Scan Library", systemImage: "wand.and.stars")
                            Spacer()
                            if isScanningLibrary {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isScanningLibrary)

                    if let result = scanResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Re-applies your current rules to all existing clips. Previously tagged highlights will be updated to match.")
                }
            }
            .navigationTitle("Auto-Highlight Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func scanLibrary() async {
        isScanningLibrary = true
        scanResult = nil
        do {
            let changed = try await MainActor.run {
                try AutoHighlightSettings.shared.scanLibrary(for: athlete, context: modelContext)
            }
            scanResult = changed == 0
                ? "All clips are already up to date."
                : "\(changed) clip\(changed == 1 ? "" : "s") updated."
        } catch {
            scanResult = "Scan failed: \(error.localizedDescription)"
        }
        isScanningLibrary = false
    }
}
