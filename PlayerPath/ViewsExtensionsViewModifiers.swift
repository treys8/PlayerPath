//
//  ViewModifiers.swift
//  PlayerPath
//
//  Created by Assistant on 10/26/25.
//

import SwiftUI

// MARK: - Custom View Modifiers

extension View {
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

// MARK: - Navigation Bar Modifiers
extension View {
    /// Standard navigation bar for tab root views (large display mode)
    func tabRootNavigationBar(title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
    }
}