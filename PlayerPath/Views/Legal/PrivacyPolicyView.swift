//
//  PrivacyPolicyView.swift
//  PlayerPath
//
//  Privacy Policy for App Store compliance
//

import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.displayLarge)

                Text("Last updated: March 1, 2026")
                    .font(.bodyMedium)
                    .foregroundColor(.secondary)

                Divider()

                // Content sections
                PolicySection(
                    title: "Introduction",
                    content: """
                    Welcome to PlayerPath. We respect your privacy and are committed to protecting your personal data. This privacy policy explains how we collect, use, and safeguard your information when you use our baseball and softball video tracking application.
                    """
                )

                PolicySection(
                    title: "Information We Collect",
                    content: """
                    We collect the following types of information:

                    • Account Information: Email address, name, and password (encrypted)
                    • Profile Data: Athlete names, seasons, games, and practice information
                    • Video Content: Videos you record are stored locally on your device and uploaded to Firebase Storage for cloud backup and cross-device access.
                    • Usage Statistics: Play results, batting statistics, game scores
                    • Device Information: Device type, operating system version for app optimization
                    • Sync Data: When you use our cross-device sync feature, data is stored in Firebase Firestore
                    • Push Notification Token: Your device token is stored in Firestore to deliver in-app and push notifications
                    • Biometric Data: If you enable Face ID, your biometric credentials are managed by iOS and never accessed or stored by us
                    """
                )

                PolicySection(
                    title: "How We Use Your Information",
                    content: """
                    We use your information to:

                    • Provide and maintain the PlayerPath service
                    • Enable cross-device synchronization of your data
                    • Calculate and display your performance statistics
                    • Improve and optimize our app based on usage patterns
                    • Send important service announcements (if you opt in)
                    • Respond to your support requests
                    """
                )

                PolicySection(
                    title: "Data Storage and Security",
                    content: """
                    • Video files are stored locally on your device in the app's secure container
                    • Video files are uploaded to Firebase Storage (Google Cloud) for cloud backup and cross-device access
                    • Account data and metadata are stored using Firebase Authentication and Firestore
                    • All data transmission uses industry-standard encryption (HTTPS/TLS)
                    • We implement appropriate security measures to protect against unauthorized access
                    """
                )

                PolicySection(
                    title: "Third-Party Services",
                    content: """
                    We use the following third-party services:

                    • Firebase Authentication (Google): Account sign-in and identity management
                    • Firebase Firestore (Google): Cloud database for syncing app data
                    • Firebase Storage (Google): Cloud storage for videos shared with coaches
                    • Firebase Analytics (Google): Anonymous usage analytics to improve the app
                    • Apple Sign In: Optional authentication method
                    • Apple StoreKit: Subscription and in-app purchase processing

                    These services have their own privacy policies governing their use of your information.
                    """
                )

                PolicySection(
                    title: "Data Sharing",
                    content: """
                    We do not sell, trade, or rent your personal information to third parties.

                    We may share data only in these circumstances:
                    • With your explicit consent (e.g., sharing videos with coaches)
                    • To comply with legal obligations
                    • To protect our rights and safety
                    """
                )

                PolicySection(
                    title: "Your Rights",
                    content: """
                    You have the right to:

                    • Access your personal data
                    • Export your data in a portable format
                    • Correct inaccurate data
                    • Delete your account and all associated data
                    • Opt out of optional data collection
                    • Withdraw consent at any time

                    To exercise these rights, use the "Export Data" and "Delete Account" options in the app settings.
                    """
                )

                PolicySection(
                    title: "Data Retention",
                    content: """
                    • We retain your data as long as your account is active
                    • When you delete your account, all data is permanently removed within 30 days
                    • Video files on your device are deleted when you uninstall the app
                    • Backup copies are automatically deleted after 30 days
                    """
                )

                PolicySection(
                    title: "Children's Privacy",
                    content: """
                    PlayerPath may be used by parents to track their children's athletic performance. We do not knowingly collect personal information from children under 13 without parental consent. Parents are responsible for managing profiles and data for their children.
                    """
                )

                PolicySection(
                    title: "Changes to This Policy",
                    content: """
                    We may update this privacy policy from time to time. We will notify you of any changes by posting the new policy in the app and updating the "Last updated" date. Continued use of the app after changes constitutes acceptance of the updated policy.
                    """
                )

                PolicySection(
                    title: "Contact Us",
                    content: """
                    If you have questions about this privacy policy or your data, please contact us at:

                    Email: support@playerpath.net

                    For data deletion requests, use the "Delete Account" option in the app or email us at the address above.
                    """
                )
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PolicySection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.displayMedium)

            Text(content)
                .font(.bodyLarge)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
