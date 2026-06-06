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

    /// Sizing for an empty/loading/error state inside the coach video player's
    /// annotation tabs. Inline (portrait phone, one outer ScrollView) gives the
    /// state a padded natural height so it doesn't collapse; otherwise it fills
    /// its fixed-height region in the iPad/landscape sidebar.
    @ViewBuilder
    func tabStateFrame(inline: Bool) -> some View {
        if inline {
            self.frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            self.frame(maxHeight: .infinity)
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