//
//  KeyboardShortcuts.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

extension View {
    @ViewBuilder
    func addKeyboardShortcuts() -> some View {
        self
            .keyboardShortcut("1", modifiers: .command)
            .keyboardShortcut("2", modifiers: .command)
            .keyboardShortcut("3", modifiers: .command)
            .keyboardShortcut("4", modifiers: .command)
            .keyboardShortcut("5", modifiers: .command)
            .keyboardShortcut("6", modifiers: .command)
            .keyboardShortcut("7", modifiers: .command)
            .keyboardShortcut("8", modifiers: .command)
    }
}
