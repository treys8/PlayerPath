//
//  AccessibilityExtensions.swift
//  PlayerPath
//
//  Created by Assistant on 10/26/25.
//

import SwiftUI

// MARK: - Accessibility Helpers
extension View {
    /// Adds semantic meaning for form validation status
    func validationAccessibility(isValid: Bool, message: String) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityValue(isValid ? "Valid" : "Invalid")
            .accessibilityHint(message)
    }
    
    /// Adds loading state accessibility
    func loadingAccessibility(isLoading: Bool, loadingMessage: String = "Loading") -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityValue(isLoading ? loadingMessage : "")
            .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
    }
    
    /// Adds form completion accessibility
    func formCompletionAccessibility(canSubmit: Bool, requirements: String) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityValue(canSubmit ? "Form complete" : "Form incomplete")
            .accessibilityHint(requirements)
    }
}

// MARK: - Accessibility Identifiers
enum AccessibilityIdentifiers {
    // Authentication
    static let signInEmailField = "sign_in_email_field"
    static let signInPasswordField = "sign_in_password_field"
    static let signInDisplayNameField = "sign_in_display_name_field"
    static let signInSubmitButton = "sign_in_submit_button"
    static let signInToggleButton = "sign_in_toggle_button"
    
    // Athletes
    static let athleteNameField = "athlete_name_field"
    static let athleteList = "athlete_list"
    static let addAthleteButton = "add_athlete_button"
    
    // Navigation
    static let profileMenu = "profile_menu"
    static let signOutButton = "sign_out_button"
    static let securitySettingsButton = "security_settings_button"
}