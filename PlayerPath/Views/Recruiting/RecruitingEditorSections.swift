//
//  RecruitingEditorSections.swift
//  PlayerPath
//
//  Form sections for the recruiting editor that branch by sport / handle PII,
//  plus the optional-String binding bridge used throughout the editor.
//

import SwiftUI

// MARK: - Optional String binding bridge

extension Binding where Value == String? {
    /// Bridges an optional model String to a non-optional TextField/Picker
    /// binding. Empty input maps back to nil so we don't persist "".
    func orEmpty() -> Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - Baseball / softball

/// Position, handedness, and the opt-in self-entered measurables row. Coaches
/// discount self-logged HS batting/pitching stats, so this is bio — clearly
/// labeled athlete-entered — not a tracked-stat band.
struct RecruitingBaseballSection: View {
    @Binding var info: RecruitingInfo

    var body: some View {
        Section("Position & Handedness") {
            TextField("Primary position (e.g. SS)", text: $info.primaryPosition.orEmpty())
            TextField("Other positions (e.g. 2B, OF)", text: $info.secondaryPosition.orEmpty())
            Picker("Bats", selection: $info.bats.orEmpty()) {
                Text("—").tag("")
                Text("Right").tag("R")
                Text("Left").tag("L")
                Text("Switch").tag("S")
            }
            Picker("Throws", selection: $info.throwsHand.orEmpty()) {
                Text("—").tag("")
                Text("Right").tag("R")
                Text("Left").tag("L")
            }
        }

        Section {
            Toggle("Show measurables", isOn: $info.showMeasurables)
            if info.showMeasurables {
                RecruitingNumberField("60-yard dash", unit: "sec", value: $info.sixtyYardDash)
                RecruitingNumberField("Exit velo", unit: "mph", value: $info.exitVelo)
                RecruitingNumberField("Throwing velo", unit: "mph", value: $info.throwingVelo)
                RecruitingNumberField("Pitch velo", unit: "mph", value: $info.pitchVelo)
            }
        } header: {
            Text("Measurables")
        } footer: {
            Text("Self-reported by the athlete. Shown on your profile as athlete-entered, not verified.")
        }
    }
}

// MARK: - PII (per-field opt-in)

/// GPA + contact info, each with an explicit opt-in. Off by default — these
/// only appear on the profile when toggled on. The publish-time consent gate
/// for minors arrives with Phase 2.
struct RecruitingPIISection: View {
    @Binding var info: RecruitingInfo

    var body: some View {
        Section {
            RecruitingNumberField("GPA", value: $info.gpa)
            Toggle("Show GPA on profile", isOn: $info.includeGPA)
        } footer: {
            Text("Optional. Off by default.")
        }

        Section {
            TextField("Contact email", text: $info.contactEmail.orEmpty())
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Toggle("Show email on profile", isOn: $info.includeContactEmail)

            TextField("Contact phone", text: $info.contactPhone.orEmpty())
                .keyboardType(.phonePad)
            Toggle("Show phone on profile", isOn: $info.includeContactPhone)
        } header: {
            Text("Contact")
        } footer: {
            Text("Each field appears on your profile only when its toggle is on. For a minor, the account owner controls what's shared.")
        }
    }
}
