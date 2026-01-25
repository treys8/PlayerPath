//
//  ContactSupportView.swift
//  PlayerPath
//
//  Contact support and feedback form
//

import SwiftUI

struct ContactSupportView: View {
    @State private var subject = ""
    @State private var message = ""
    @State private var selectedCategory: SupportCategory = .general
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.largeTitle)
                        .foregroundColor(.blue)

                    Text("Get Help")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("We're here to help! Send us your questions, feedback, or bug reports.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Category") {
                Picker("Select Category", selection: $selectedCategory) {
                    ForEach(SupportCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.icon)
                            .tag(category)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Subject") {
                TextField("Brief description", text: $subject)
            }

            Section {
                TextEditor(text: $message)
                    .frame(minHeight: 150)
            } header: {
                Text("Message")
            } footer: {
                Text("Please provide as much detail as possible to help us assist you better.")
            }

            Section {
                Button {
                    sendSupportEmail()
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Send Message")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(subject.isEmpty || message.isEmpty)
            }

            Section("Other Ways to Reach Us") {
                Link(destination: URL(string: "mailto:support@playerpath.app")!) {
                    HelpRowLabel(
                        icon: "envelope",
                        title: "Email Support",
                        subtitle: "support@playerpath.app"
                    )
                }

                Link(destination: URL(string: "https://playerpath.app/help")!) {
                    HelpRowLabel(
                        icon: "safari",
                        title: "Help Center",
                        subtitle: "playerpath.app/help"
                    )
                }
            }
        }
        .navigationTitle("Contact Support")
        .alert("Message Sent", isPresented: $showingAlert) {
            Button("OK") {
                // Clear form
                subject = ""
                message = ""
                selectedCategory = .general
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func sendSupportEmail() {
        // Track support contact submission
        AnalyticsService.shared.trackSupportContactSubmitted(category: selectedCategory.displayName)

        // Construct email URL
        let emailBody = """
        Category: \(selectedCategory.displayName)

        \(message)

        ---
        App Version: 1.0.0
        Device: \(UIDevice.current.model)
        iOS Version: \(UIDevice.current.systemVersion)
        """

        let emailSubject = subject
        let emailTo = "support@playerpath.app"

        let coded = "mailto:\(emailTo)?subject=\(emailSubject)&body=\(emailBody)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)

        if let emailURL = coded.flatMap({ URL(string: $0) }) {
            if UIApplication.shared.canOpenURL(emailURL) {
                UIApplication.shared.open(emailURL)
                alertMessage = "Your email app will open with a pre-filled message."
                showingAlert = true
            } else {
                alertMessage = "Please send an email to support@playerpath.app with your question."
                showingAlert = true
            }
        }
    }
}

enum SupportCategory: String, CaseIterable, Identifiable {
    case general = "general"
    case bug = "bug"
    case feature = "feature"
    case account = "account"
    case sync = "sync"
    case video = "video"
    case statistics = "statistics"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "General Question"
        case .bug: return "Bug Report"
        case .feature: return "Feature Request"
        case .account: return "Account Issue"
        case .sync: return "Sync Problem"
        case .video: return "Video Issue"
        case .statistics: return "Statistics Question"
        }
    }

    var icon: String {
        switch self {
        case .general: return "questionmark.circle"
        case .bug: return "ladybug"
        case .feature: return "lightbulb"
        case .account: return "person.circle"
        case .sync: return "arrow.triangle.2.circlepath"
        case .video: return "video"
        case .statistics: return "chart.bar"
        }
    }
}

#Preview {
    NavigationStack {
        ContactSupportView()
    }
}
