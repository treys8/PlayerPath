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
            RecruitingTextField("Primary", prompt: "SS",
                                text: $info.primaryPosition.orEmpty(),
                                autocapitalization: .characters, autocorrect: false)
            RecruitingTextField("Other", prompt: "2B, OF",
                                text: $info.secondaryPosition.orEmpty(),
                                autocapitalization: .characters, autocorrect: false)
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
/// only appear on the profile when toggled on.
///
/// Each toggle is disabled while its field is empty, AND cleared the moment the
/// field is emptied. Masking alone isn't enough: a toggle left ON over a blank
/// field is armed, and would publish a minor's email the instant someone typed
/// one — no second decision, no second look at the consent copy.
struct RecruitingPIISection: View {
    @Binding var info: RecruitingInfo

    private var hasGPA: Bool { info.gpa != nil }
    private var hasEmail: Bool { info.contactEmail?.isEmpty == false }
    private var hasPhone: Bool { info.contactPhone?.isEmpty == false }

    var body: some View {
        Section {
            RecruitingNumberField("GPA", value: $info.gpa)
            Toggle("Show GPA on profile", isOn: $info.includeGPA)
                .disabled(!hasGPA)
        } header: {
            Text("Academics")
        } footer: {
            Text("Optional. Off by default.")
        }
        .onChange(of: info.gpa) { _, newValue in
            if newValue == nil { info.includeGPA = false }
        }

        Section {
            RecruitingTextField("Email", prompt: "you@example.com",
                                text: $info.contactEmail.orEmpty(),
                                keyboard: .emailAddress,
                                autocapitalization: .never, autocorrect: false)
            Toggle("Show email on profile", isOn: $info.includeContactEmail)
                .disabled(!hasEmail)

            RecruitingTextField("Phone", prompt: "(555) 555-5555",
                                text: $info.contactPhone.orEmpty(),
                                keyboard: .phonePad,
                                autocapitalization: .never, autocorrect: false)
            Toggle("Show phone on profile", isOn: $info.includeContactPhone)
                .disabled(!hasPhone)
        } header: {
            Text("Contact")
        } footer: {
            Text("Each field appears on your profile only when its toggle is on. For a minor, the account owner controls what's shared.")
        }
        .onChange(of: info.contactEmail) { _, newValue in
            if newValue?.isEmpty != false { info.includeContactEmail = false }
        }
        .onChange(of: info.contactPhone) { _, newValue in
            if newValue?.isEmpty != false { info.includeContactPhone = false }
        }
    }
}
