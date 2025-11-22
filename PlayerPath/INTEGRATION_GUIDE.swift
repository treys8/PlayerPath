//
//  INTEGRATION_GUIDE.swift
//  PlayerPath - Coach Dashboard Integration
//
//  Quick reference for integrating the coach dashboard
//

import SwiftUI

/*
 
 ═══════════════════════════════════════════════════════════
   STEP 1: Update Your App's Root View
 ═══════════════════════════════════════════════════════════
 
 Find your main ContentView or root view and add role-based routing:
 */

struct AppRootView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    
    var body: some View {
        Group {
            if authManager.isSignedIn {
                // Route based on user role
                if authManager.userRole == .coach {
                    CoachDashboardView()
                } else {
                    // Your existing athlete app
                    MainAppView() // or whatever your main view is called
                }
            } else {
                SignInView()
            }
        }
        .environmentObject(authManager)
    }
}

/*
 
 ═══════════════════════════════════════════════════════════
   STEP 2: Add Coach Sharing to Athlete Views
 ═══════════════════════════════════════════════════════════
 
 Let athletes create and manage shared folders. Add this to your
 athlete's profile or settings view:
 */

struct AthleteSharedFoldersView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var sharedFolderManager = SharedFolderManager.shared
    @State private var showingCreateFolder = false
    
    var body: some View {
        List {
            Section("My Shared Folders") {
                ForEach(sharedFolderManager.athleteFolders) { folder in
                    NavigationLink(destination: AthleteFolderDetailView(folder: folder)) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(folder.name)
                                    .font(.headline)
                                Text("\(folder.sharedWithCoachIDs.count) coach(es)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            Button(action: {
                showingCreateFolder = true
            }) {
                Label("Create Coach Folder", systemImage: "plus.circle.fill")
            }
            .disabled(!authManager.isPremiumUser) // Premium feature
        }
        .navigationTitle("Coach Sharing")
        .sheet(isPresented: $showingCreateFolder) {
            CreateSharedFolderView()
        }
        .task {
            if let userID = authManager.userID {
                try? await sharedFolderManager.loadAthleteFolders(athleteID: userID)
            }
        }
    }
}

/*
 
 ═══════════════════════════════════════════════════════════
   STEP 3: Create Folder Creation View
 ═══════════════════════════════════════════════════════════
 */

struct CreateSharedFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var sharedFolderManager = SharedFolderManager.shared
    
    @State private var folderName = ""
    @State private var coachEmail = ""
    @State private var canUpload = true
    @State private var canComment = true
    @State private var canDelete = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Folder Details") {
                    TextField("Folder Name", text: $folderName)
                        .textInputAutocapitalization(.words)
                }
                
                Section("Invite Coach") {
                    TextField("Coach Email", text: $coachEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .disableAutocorrection(true)
                }
                
                Section("Coach Permissions") {
                    Toggle("Can Upload Videos", isOn: $canUpload)
                    Toggle("Can Add Comments", isOn: $canComment)
                    Toggle("Can Delete Videos", isOn: $canDelete)
                }
                
                Section {
                    Text("The coach will receive an invitation to access this folder once you create it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New Shared Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await createFolder()
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private var isValid: Bool {
        !folderName.isEmpty && !coachEmail.isEmpty
    }
    
    private func createFolder() async {
        guard let athleteID = authManager.userID,
              let athleteName = authManager.userDisplayName ?? authManager.userEmail else {
            return
        }
        
        do {
            // Create folder
            let folderID = try await sharedFolderManager.createFolder(
                name: folderName,
                forAthlete: athleteID,
                isPremium: authManager.isPremiumUser
            )
            
            // Create permissions
            let permissions = FolderPermissions(
                canUpload: canUpload,
                canComment: canComment,
                canDelete: canDelete
            )
            
            // Send invitation
            try await sharedFolderManager.inviteCoachToFolder(
                coachEmail: coachEmail,
                folderID: folderID,
                athleteID: athleteID,
                athleteName: athleteName,
                folderName: folderName,
                permissions: permissions
            )
            
            dismiss()
        } catch {
            print("❌ Failed to create folder: \(error)")
        }
    }
}

/*
 
 ═══════════════════════════════════════════════════════════
   STEP 4: Update Your App Delegate or Main App File
 ═══════════════════════════════════════════════════════════
 
 Make sure Firebase is initialized:
 */

import FirebaseCore

@main
struct PlayerPathApp: App {
    init() {
        FirebaseApp.configure()
    }
    
    @StateObject private var authManager = ComprehensiveAuthManager()
    
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(authManager)
        }
    }
}

/*
 
 ═══════════════════════════════════════════════════════════
   STEP 5: Enable Firebase Services
 ═══════════════════════════════════════════════════════════
 
 In Firebase Console:
 
 1. **Authentication**
    - Enable Email/Password authentication
 
 2. **Firestore Database**
    - Create database (start in production mode or test mode)
    - Deploy security rules from COACH_SHARING_ARCHITECTURE.md
 
 3. **Storage**
    - Enable Firebase Storage
    - Deploy storage rules from COACH_SHARING_ARCHITECTURE.md
 
 4. **Download GoogleService-Info.plist**
    - Add to Xcode project
    - Make sure it's included in your target
 
 ═══════════════════════════════════════════════════════════
   STEP 6: Test the Flow
 ═══════════════════════════════════════════════════════════
 
 1. Sign up as Athlete
    - Create account with role "Athlete"
    - Create a shared folder
    - Invite a coach by email
 
 2. Sign up as Coach
    - Create account with role "Coach"
    - Use the same email from invitation
    - Accept invitation
    - View shared folder
    - Upload video
    - Add annotation
 
 3. Back to Athlete
    - View shared folder
    - See coach's video
    - Read coach's annotation
    - Add reply annotation
 
 ═══════════════════════════════════════════════════════════
   TROUBLESHOOTING
 ═══════════════════════════════════════════════════════════
 
 **Issue: Videos not uploading**
 - Check Firebase Storage is enabled
 - Verify storage rules allow authenticated writes
 - Check VideoCloudManager.uploadVideoToSharedFolder() implementation
 
 **Issue: Invitations not working**
 - Verify email is exactly the same (case-insensitive)
 - Check Firestore "invitations" collection exists
 - Confirm invitation status is "pending"
 
 **Issue: Can't see annotations**
 - Check Firestore security rules allow subcollection reads
 - Verify annotation is saved to correct video ID
 - Confirm user has access to parent folder
 
 **Issue: Wrong view after sign in**
 - Check authManager.userRole is loading correctly
 - Verify Firestore user profile has "role" field
 - Confirm routing logic in AppRootView
 
 ═══════════════════════════════════════════════════════════
   OPTIONAL ENHANCEMENTS
 ═══════════════════════════════════════════════════════════
 
 1. **Email Notifications**
    - Set up Firebase Cloud Functions
    - Send email when invitation created
    - Send email when video uploaded
    - Send email when annotation added
 
 2. **Push Notifications**
    - Enable Firebase Cloud Messaging
    - Send push when coach comments
    - Send push when athlete responds
 
 3. **Analytics**
    - Add Firebase Analytics
    - Track folder creation
    - Track video uploads by role
    - Track annotation engagement
 
 4. **Deep Links**
    - Set up Universal Links
    - Link directly to specific folder from email
    - Link directly to video with annotations
 
 */

// MARK: - That's it! You're all set up! 🎉
