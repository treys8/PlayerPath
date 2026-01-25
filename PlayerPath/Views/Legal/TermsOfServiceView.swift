//
//  TermsOfServiceView.swift
//  PlayerPath
//
//  Terms of Service for App Store compliance
//

import SwiftUI

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Terms of Service")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Last updated: January 25, 2026")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Divider()

                // Content sections
                TermsSection(
                    title: "Acceptance of Terms",
                    content: """
                    By accessing and using PlayerPath ("the App"), you accept and agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the App.
                    """
                )

                TermsSection(
                    title: "Description of Service",
                    content: """
                    PlayerPath is a mobile application designed to help baseball and softball players track their performance through video recording, play tagging, and statistical analysis. The App allows users to:

                    • Record and store videos of at-bats and practices
                    • Tag play results (hits, outs, walks, etc.)
                    • Track batting statistics and performance metrics
                    • Manage seasons, games, and practice sessions
                    • Sync data across devices (optional)
                    """
                )

                TermsSection(
                    title: "User Accounts",
                    content: """
                    • You must create an account to use the App
                    • You are responsible for maintaining the confidentiality of your account credentials
                    • You are responsible for all activities that occur under your account
                    • You must provide accurate and complete information
                    • You must be at least 13 years old or have parental consent to create an account
                    • One person may not maintain more than one account
                    """
                )

                TermsSection(
                    title: "Acceptable Use",
                    content: """
                    You agree to use the App only for lawful purposes. You will not:

                    • Upload or record content that violates any laws or third-party rights
                    • Upload content that is offensive, threatening, or inappropriate
                    • Attempt to gain unauthorized access to the App or other users' data
                    • Use the App to harass, abuse, or harm others
                    • Reverse engineer, decompile, or disassemble the App
                    • Use automated systems or bots to access the App
                    • Violate any applicable laws or regulations
                    """
                )

                TermsSection(
                    title: "Content Ownership and Rights",
                    content: """
                    • You retain all rights to the videos and content you create
                    • By using the App, you grant us a limited license to store and process your content to provide the service
                    • You represent that you have the right to record and upload all content
                    • You are responsible for obtaining necessary permissions for recording individuals
                    • We do not claim ownership of your content
                    """
                )

                TermsSection(
                    title: "Privacy and Data",
                    content: """
                    Your use of the App is also governed by our Privacy Policy. By using the App, you consent to our collection and use of data as described in the Privacy Policy.

                    • Video files are stored locally on your device
                    • Metadata and statistics may be synced to cloud storage
                    • We implement security measures to protect your data
                    • You can export or delete your data at any time
                    """
                )

                TermsSection(
                    title: "Service Availability",
                    content: """
                    • We strive to provide reliable service but cannot guarantee 100% uptime
                    • The App may be temporarily unavailable due to maintenance or technical issues
                    • We reserve the right to modify or discontinue features with or without notice
                    • We are not liable for any disruption or loss of data due to service interruptions
                    • Beta features are provided "as is" and may change or be removed
                    """
                )

                TermsSection(
                    title: "Limitation of Liability",
                    content: """
                    TO THE MAXIMUM EXTENT PERMITTED BY LAW:

                    • The App is provided "AS IS" without warranties of any kind
                    • We are not responsible for lost, corrupted, or deleted data
                    • We are not liable for any indirect, incidental, or consequential damages
                    • Our total liability shall not exceed the amount you paid for the App (if any)
                    • You are responsible for backing up important data
                    • We are not responsible for the accuracy of statistics or calculations
                    """
                )

                TermsSection(
                    title: "Account Termination",
                    content: """
                    We reserve the right to suspend or terminate your account if:

                    • You violate these Terms of Service
                    • You engage in fraudulent or illegal activity
                    • Your account has been inactive for an extended period
                    • We are required to do so by law

                    You may terminate your account at any time using the "Delete Account" feature in the App.
                    """
                )

                TermsSection(
                    title: "Premium Features",
                    content: """
                    • Some features may require a premium subscription (future)
                    • Subscription fees are non-refundable except as required by law
                    • Subscriptions auto-renew unless cancelled before the renewal date
                    • We may change pricing with notice to existing subscribers
                    • Free features may become premium features with notice
                    """
                )

                TermsSection(
                    title: "Intellectual Property",
                    content: """
                    • The App and its original content, features, and functionality are owned by PlayerPath
                    • The PlayerPath name, logo, and trademarks are our property
                    • You may not use our intellectual property without permission
                    • Third-party trademarks are property of their respective owners
                    """
                )

                TermsSection(
                    title: "Indemnification",
                    content: """
                    You agree to indemnify and hold harmless PlayerPath and its affiliates from any claims, damages, or expenses arising from:

                    • Your use of the App
                    • Your violation of these Terms
                    • Your violation of any rights of another person or entity
                    • Content you upload or create
                    """
                )

                TermsSection(
                    title: "Dispute Resolution",
                    content: """
                    • These Terms are governed by the laws of [Your State/Country]
                    • Any disputes shall be resolved through binding arbitration
                    • You waive the right to participate in class action lawsuits
                    • Small claims court remains available for qualifying disputes
                    """
                )

                TermsSection(
                    title: "Changes to Terms",
                    content: """
                    We may update these Terms of Service from time to time. We will notify you of any material changes by:

                    • Posting the new terms in the App
                    • Updating the "Last updated" date
                    • Sending an in-app notification (for significant changes)

                    Continued use of the App after changes constitutes acceptance of the updated terms.
                    """
                )

                TermsSection(
                    title: "Severability",
                    content: """
                    If any provision of these Terms is found to be unenforceable, the remaining provisions will remain in full effect.
                    """
                )

                TermsSection(
                    title: "Contact Information",
                    content: """
                    For questions about these Terms of Service, please contact us at:

                    Email: legal@playerpath.app

                    For technical support, use the Help & Support section in the App.
                    """
                )
            }
            .padding()
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsSection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(content)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    NavigationStack {
        TermsOfServiceView()
    }
}
