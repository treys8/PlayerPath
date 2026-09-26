//
//  RecruitingStatePicker.swift
//  PlayerPath
//
//  State row for the recruiting editor. Was free text, which let "Mississippi"
//  autocapitalize to "MISSISSIPPI" and print as "Starkville, MISSISSIPPI" on the
//  public page. The page shows `state` verbatim (RecruitingInfo.locationLine), so
//  the picker stores the two-letter code.
//

import SwiftUI

enum USState {
    /// 50 states + DC + PR, in display order.
    static let all: [(code: String, name: String)] = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"),
        ("CA", "California"), ("CO", "Colorado"), ("CT", "Connecticut"), ("DE", "Delaware"),
        ("DC", "District of Columbia"), ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"),
        ("ID", "Idaho"), ("IL", "Illinois"), ("IN", "Indiana"), ("IA", "Iowa"),
        ("KS", "Kansas"), ("KY", "Kentucky"), ("LA", "Louisiana"), ("ME", "Maine"),
        ("MD", "Maryland"), ("MA", "Massachusetts"), ("MI", "Michigan"), ("MN", "Minnesota"),
        ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"), ("NE", "Nebraska"),
        ("NV", "Nevada"), ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"),
        ("NY", "New York"), ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"),
        ("OK", "Oklahoma"), ("OR", "Oregon"), ("PA", "Pennsylvania"), ("PR", "Puerto Rico"),
        ("RI", "Rhode Island"), ("SC", "South Carolina"), ("SD", "South Dakota"), ("TN", "Tennessee"),
        ("TX", "Texas"), ("UT", "Utah"), ("VT", "Vermont"), ("VA", "Virginia"),
        ("WA", "Washington"), ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming")
    ]

    /// Maps a code or full name in any case ("ms", "MISSISSIPPI") to its code.
    /// Anything unrecognised (a Canadian province, a typo) comes back trimmed but
    /// otherwise untouched — never dropped.
    static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return raw }
        let match = all.first {
            $0.code.caseInsensitiveCompare(trimmed) == .orderedSame
                || $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        return match?.code ?? trimmed
    }

    static func isKnown(_ code: String) -> Bool {
        all.contains { $0.code == code }
    }
}

struct RecruitingStatePicker: View {
    @Binding var state: String?

    /// A saved value the list doesn't carry, captured ONCE. Read off the live
    /// binding instead and the row vanishes the moment another state is picked,
    /// leaving no way back to the athlete's original entry.
    @State private var legacyValue: String?

    init(state: Binding<String?>) {
        self._state = state
        let current = state.wrappedValue ?? ""
        _legacyValue = State(initialValue:
            current.isEmpty || USState.isKnown(current) ? nil : current)
    }

    var body: some View {
        Picker("State", selection: $state.orEmpty()) {
            Text("—").tag("")
            if let legacyValue {
                Text(legacyValue).tag(legacyValue)
            }
            ForEach(USState.all, id: \.code) { entry in
                Text(entry.name).tag(entry.code)
            }
        }
    }
}
