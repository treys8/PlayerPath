//
//  ViewModifiers.swift
//  PlayerPath
//
//  Created by Assistant on 10/26/25.
//

import SwiftUI

// MARK: - Custom View Modifiers

extension View {
    /// Adds haptic feedback to button taps
    func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        self.onTapGesture {
            HapticManager.shared.buttonTap()
        }
    }
    
    /// Standard PlayerPath card styling
    func cardStyle() -> some View {
        self
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    /// Standard PlayerPath button styling
    func primaryButtonStyle() -> some View {
        self
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
    
    /// Conditional view modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Validation Styling
struct ValidationStyle: ViewModifier {
    let isValid: Bool
    let showValidation: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        showValidation ? (isValid ? Color.green : Color.red) : Color.clear,
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func validationStyle(isValid: Bool, showValidation: Bool) -> some View {
        modifier(ValidationStyle(isValid: isValid, showValidation: showValidation))
    }
}

// MARK: - Navigation Bar Modifiers
extension View {
    /// Standard navigation bar for tab root views (large display mode)
    func tabRootNavigationBar(title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
    }
    
    /// Standard navigation bar for regular views (inline display mode)
    func standardNavigationBar(title: String, displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(displayMode)
    }
    
    /// Child navigation bar for pushed/detail views (inline display mode)
    func childNavigationBar(title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}