//
//  ContactSupportView.swift
//  PlayerPath
//
//  Contact support and feedback form
//

import SwiftUI

struct ContactSupportView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var subject = ""
    @State private var message = ""
    @State private var selectedCategory: SupportCategory = .general
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingNoMailAlert = false
    @FocusState private var focusedField: FormField?

    private enum FormField: Hashable { case subject, message }

    /// Coaches don't have statistics, so hide that category for them.
    private var availableCategories: [SupportCategory] {
        authManager.userRole == .coach
            ? SupportCategory.allCases.filter { $0 != .statistics }
            : SupportCategory.allCases
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.largeTitle)
                        .foregroundColor(.brandNavy)

                    Text("Get Help")
                        .font(.displayMedium)

                    Text("We're here to help! Send us your questions, feedback, or bug reports.")
                        .font(.bodyMedium)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Category") {
                Picker("Select Category", selection: $selectedCategory) {
                    ForEach(availableCategories) { category in
                        Label(category.displayName, systemImage: category.icon)
                            .tag(category)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Subject") {
                TextField("Brief description", text: $subject)
                    .focused($focusedField, equals: .subject)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .message }
            }

            Section {
                TextEditor(text: $message)
                    .frame(minHeight: 150)
                    .focused($focusedField, equals: .message)
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
                Link(destination: URL(string: "mailto:\(AuthConstants.supportEmail)") ?? URL(string: "https://playerpath.net")!) {
                // Force unwrap above is safe — hardcoded valid URL as nil-coalescing fallback
                    HelpRowLabel(
                        icon: "envelope",
                        title: "Email Support",
                        subtitle: AuthConstants.supportEmail
                    )
                }

            }
        }
        .navigationTitle("Contact Support")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .toast(isPresenting: $showingAlert, message: alertMessage)
        .alert("No Mail App Found", isPresented: $showingNoMailAlert) {
            Button("Copy Email Address") {
                UIPasteboard.general.string = AuthConstants.supportEmail
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("We couldn't open Mail on this device. Please email us directly at \(AuthConstants.supportEmail).")
        }
    }

    private func sendSupportEmail() {
        // Track support contact submission
        AnalyticsService.shared.trackSupportContactSubmitted(category: selectedCategory.displayName)

        // Construct email URL
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let emailBody = """
        Category: \(selectedCategory.displayName)

        \(message)

        ---
        App Version: \(appVersion) (\(buildNumber))
        Device: \(UIDevice.current.model)
        iOS Version: \(UIDevice.current.systemVersion)
        """

        let emailSubject = subject
        let emailTo = AuthConstants.supportEmail

        let coded = "mailto:\(emailTo)?subject=\(emailSubject)&body=\(emailBody)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)

        if let emailURL = coded.flatMap({ URL(string: $0) }),
           UIApplication.shared.canOpenURL(emailURL) {
            UIApplication.shared.open(emailURL)
            subject = ""
            message = ""
            selectedCategory = .general
            // Honest copy: we opened a pre-filled draft, we did not "send" anything.
            alertMessage = "Opening Mail…"
            showingAlert = true
        } else {
            // No mail client configured — surface the address instead of failing silently.
            showingNoMailAlert = true
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
            .environmentObject(ComprehensiveAuthManager())
    }
}
