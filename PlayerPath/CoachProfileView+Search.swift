//
//  CoachProfileView+Search.swift
//  PlayerPath
//
//  Settings search for the coach profile, mirroring the athlete ProfileView
//  search. Kept in its own file so CoachProfileView stays focused.
//

import SwiftUI
import FirebaseAuth

extension CoachProfileView {
    /// Additive search-results section shown at the top of the list while a
    /// query is active. The normal settings sections remain visible below.
    @ViewBuilder
    var coachSearchSection: some View {
        if !searchText.isEmpty {
            Section("Search Results") {
                if filteredCoachSearchResults.isEmpty {
                    Text("No results for \"\(searchText)\"")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredCoachSearchResults, id: \.title) { result in
                        result.link
                    }
                }
            }
        }
    }

    var filteredCoachSearchResults: [SearchResult] {
        let query = searchText.lowercased()
        return coachSearchableItems.filter { item in
            item.title.lowercased().contains(query) ||
            item.keywords.contains(where: { $0.lowercased().contains(query) })
        }
    }

    /// Searchable destinations on the coach profile. Limited to the
    /// NavigationLink-based settings screens (the values a coach would search
    /// for); sheet-driven rows like Edit Profile / Plan are top-level already.
    var coachSearchableItems: [SearchResult] {
        var items: [SearchResult] = [
            searchItem("App Preferences", icon: "slider.horizontal.3",
                       keywords: ["app", "preferences", "haptics", "tips", "analytics", "interface"]) {
                UserPreferencesView()
            },
            searchItem("Video Recording", icon: "video.fill",
                       keywords: ["video", "recording", "quality", "camera", "resolution", "fps", "4k"]) {
                VideoRecordingSettingsView(role: .coach)
            },
            searchItem("Manage Storage", icon: "internaldrive",
                       keywords: ["storage", "manage", "space", "cache", "cleanup", "videos", "disk"]) {
                StorageSettingsView()
            },
            searchItem("Notifications", icon: "bell",
                       keywords: ["notifications", "alerts", "push"]) {
                NotificationSettingsView(athleteId: nil)
            },
            searchItem("Review Reminders", icon: "bell.badge",
                       keywords: ["review", "reminders", "clips", "feedback"]) {
                CoachReviewReminderSettingsView()
            },
            searchItem("Activity", icon: "bell.badge",
                       keywords: ["activity", "inbox", "notifications", "updates", "feed"]) {
                NotificationInboxView()
            },
            searchItem("Help & Support", icon: "questionmark.circle",
                       keywords: ["help", "support", "contact", "faq", "assistance"]) {
                HelpSupportView()
            },
            searchItem("About PlayerPath", icon: "info.circle",
                       keywords: ["about", "version", "info", "information"]) {
                AboutView()
            },
            searchItem("Privacy Policy", icon: "hand.raised",
                       keywords: ["privacy", "policy", "legal", "data"]) {
                PrivacyPolicyView()
            },
            searchItem("Terms of Use", icon: "doc.text",
                       keywords: ["terms", "eula", "legal", "use"]) {
                TermsOfServiceView()
            },
            searchItem("Export Data", icon: "square.and.arrow.up",
                       keywords: ["export", "data", "download", "backup", "gdpr"]) {
                DataExportView().environmentObject(authManager)
            },
            searchItem("Delete Account", icon: "trash",
                       keywords: ["delete", "account", "remove", "close", "gdpr"]) {
                AccountDeletionView().environmentObject(authManager)
            }
        ]

        // Change Password is hidden for Apple Sign In accounts — match that here.
        let provider = Auth.auth().currentUser?.providerData.first?.providerID ?? "email"
        if provider != "apple.com" {
            items.append(searchItem("Change Password", icon: "lock.rotation",
                                     keywords: ["change", "password", "reset", "security", "login"]) {
                ChangePasswordView(email: authManager.userEmail ?? "")
            })
        }

        return items
    }

    private func searchItem<Destination: View>(
        _ title: String,
        icon: String,
        keywords: [String],
        @ViewBuilder destination: () -> Destination
    ) -> SearchResult {
        SearchResult(
            title: title,
            icon: icon,
            keywords: keywords,
            link: AnyView(
                NavigationLink {
                    destination()
                } label: {
                    Label(title, systemImage: icon)
                }
            )
        )
    }
}
