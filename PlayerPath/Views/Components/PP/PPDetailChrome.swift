//
//  PPDetailChrome.swift
//  PlayerPath
//
//  Visual overhaul — shared chrome for pushed detail screens and sheets.
//  Extracted from GameDetailView so every reskinned List/Form matches: cream
//  surface, hidden system grouped background, accent tint, and editorial action
//  rows (textPrimary title + accent icon; destructive stays red).
//

import SwiftUI

/// Action rows in the cream detail chrome: `textPrimary` title with an accent
/// (orange) icon. Replaces the iOS-tint look so rows read as editorial, not
/// system blue. Apply via `.labelStyle(ActionRowLabelStyle())` — usually on the
/// enclosing `Section`.
struct ActionRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .foregroundStyle(Theme.accent)
                .frame(width: 24, alignment: .center)
            configuration.title
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

/// Destructive rows (End / Delete) stay red — re-asserts the role color when an
/// `ActionRowLabelStyle` is in scope on the enclosing section.
struct DestructiveRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .foregroundStyle(.red)
                .frame(width: 24, alignment: .center)
            configuration.title
                .foregroundStyle(.red)
        }
    }
}

extension View {
    /// The cream detail-screen chrome shared by every pushed List/Form: hide the
    /// system grouped background, paint `Theme.surface` behind it, and tint
    /// controls with the one accent. Centralizes the GameDetailView treatment so
    /// every reskinned detail screen and sheet matches.
    func ppDetailBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .tint(Theme.accent)
    }
}
