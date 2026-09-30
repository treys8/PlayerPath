//
//  LegalDocumentLayout.swift
//  PlayerPath
//
//  Shared chrome for the Privacy Policy and Terms of Use pages: cream
//  surface, one title (the nav bar's large title — no duplicate in-body
//  heading), and the post-overhaul type scale.
//

import SwiftUI

struct LegalDocumentView<Content: View>: View {
    let title: String
    let lastUpdated: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Last updated: \(lastUpdated)")
                    .font(.ppFootnote)
                    .foregroundStyle(Theme.textSecondary)

                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.surface)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}

struct LegalSection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.ppTitle3)
                .foregroundStyle(Theme.textPrimary)

            Text(content)
                .font(.ppBody)
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Wraps a legal page for `.sheet` presentation so it gets its nav-bar
/// title and a Done button (pushed call sites already have a stack).
struct LegalSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
