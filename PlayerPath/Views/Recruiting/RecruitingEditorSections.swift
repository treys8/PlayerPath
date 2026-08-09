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
    /// Publishing a child's contact details is gated on implied age — see
    /// `RecruitingInfo.contactPublishingBlocked` for the COPPA reasoning and the
    /// arithmetic. `visibleContactItems` is what actually withholds them; these
    /// toggles are disabled so the athlete isn't left arming a switch that
    /// silently does nothing.
    ///
    /// Two distinct reasons to disable, and they need DIFFERENT copy: an athlete known
    /// to be under 13, and an athlete whose grad year simply isn't set yet. Telling a
    /// parent "this athlete is under 13" when they just haven't picked a year would be
    /// both wrong and confusing, so `blocked` drives the control state while `under13`
    /// drives only the sentence that names an age.
    private var blocked: Bool { info.contactPublishingBlocked }
    private var under13: Bool { info.gradYearImpliesUnder13 }

    /// Explains why the contact/GPA toggles are off, or nil when they're available.
    private var blockedReason: String? {
        guard blocked else { return nil }
        return under13
            ? "The graduation year you picked puts this athlete under 13, so contact details and GPA aren't published. Their film, measurables and headshot still appear on the page."
            : "Add a graduation year to publish contact details. Until then they're withheld, because a page that shows a way to reach an athlete of unknown age isn't safe to publish."
    }

    var body: some View {
        Section {
            RecruitingNumberField("GPA", value: $info.gpa)
            Toggle("Show GPA on profile", isOn: $info.includeGPA)
                .disabled(!hasGPA || blocked)
        } header: {
            Text("Academics")
        } footer: {
            Text(blocked
                 ? (under13 ? "GPA isn't published for an athlete under 13."
                            : "Add a graduation year to publish GPA.")
                 : "Optional. Off by default.")
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
                .disabled(!hasEmail || blocked)

            RecruitingTextField("Phone", prompt: "(555) 555-5555",
                                text: $info.contactPhone.orEmpty(),
                                keyboard: .phonePad,
                                autocapitalization: .never, autocorrect: false)
            Toggle("Show phone on profile", isOn: $info.includeContactPhone)
                .disabled(!hasPhone || blocked)
        } header: {
            Text("Contact")
        } footer: {
            Text(blockedReason
                 ?? "Each field appears on your profile only when its toggle is on. For a minor, the account owner controls what's shared.")
        }
        .onChange(of: info.contactEmail) { _, newValue in
            if newValue?.isEmpty != false { info.includeContactEmail = false }
        }
        .onChange(of: info.contactPhone) { _, newValue in
            if newValue?.isEmpty != false { info.includeContactPhone = false }
        }
        // NOTE: the equivalent clearing for the under-13 gate is NOT here. Grad year
        // is edited in a different section of the Form (basicsSection), and an
        // `.onChange` hanging off this one isn't guaranteed to be active in a lazily
        // materialised List while the athlete is scrolled up there. It lives on the
        // picker's binding in RecruitingProfileEditorView.gradYearBinding instead —
        // on the write itself, where it always runs.
    }
}
