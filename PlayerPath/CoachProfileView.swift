//
//  CoachProfileView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Profile and settings for coaches
//

import SwiftUI

struct CoachProfileView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var sharedFolderManager = SharedFolderManager.shared
    @State private var showingSignOutAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                // Profile Section
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authManager.userDisplayName ?? "Coach")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            Text(authManager.userEmail ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption)
                                Text("Coach Account")
                                    .font(.caption)
                            }
                            .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Stats Section
                Section("Activity") {
                    HStack {
                        Label("Athletes", systemImage: "person.3.fill")
                        Spacer()
                        Text("\(sharedFolderManager.coachFolders.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Total Videos", systemImage: "video.fill")
                        Spacer()
                        Text("\(totalVideoCount)")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Account Section
                Section("Account") {
                    Button(action: {
                        showingSignOutAlert = true
                    }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
                
                // App Info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Profile")
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await authManager.signOut()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }
    
    private var totalVideoCount: Int {
        sharedFolderManager.coachFolders.reduce(0) { $0 + ($1.videoCount ?? 0) }
    }
}

// MARK: - Preview

#Preview {
    CoachProfileView()
        .environmentObject(ComprehensiveAuthManager())
}
