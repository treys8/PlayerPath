//
//  CloudKitTestView.swift
//  PlayerPath
//
//  Created by Assistant on 10/29/25.
//

import SwiftUI

struct CloudKitTestView: View {
    @State private var cloudKitManager = CloudKitManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("CloudKit Setup Test")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                // CloudKit Capability Status
                HStack {
                    Image(systemName: cloudKitManager.isCloudKitAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(cloudKitManager.isCloudKitAvailable ? .green : .orange)
                    
                    Text("CloudKit Capability: \(cloudKitManager.isCloudKitAvailable ? "Available" : "Not Configured")")
                }
                
                // iCloud Account Status (only if CloudKit is available)
                if cloudKitManager.isCloudKitAvailable {
                    HStack {
                        Image(systemName: cloudKitManager.isSignedInToiCloud ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(cloudKitManager.isSignedInToiCloud ? .green : .red)
                        
                        Text("iCloud Account: \(cloudKitManager.isSignedInToiCloud ? "Connected" : "Not Available")")
                    }
                }
                
                // Error Message
                if let error = cloudKitManager.cloudKitError, !error.isEmpty {
                    Text("Status: \(error)")
                        .font(.caption)
                        .foregroundColor(cloudKitManager.isCloudKitAvailable ? .red : .orange)
                        .multilineTextAlignment(.leading)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Button("Refresh Status") {
                cloudKitManager.checkCloudKitAvailability()
            }
            .buttonStyle(.bordered)
            
            // Show register button if there's a container registration issue
            if let error = cloudKitManager.cloudKitError, 
               error.contains("register") || error.contains("container") {
                Button("Register CloudKit Container") {
                    cloudKitManager.registerContainer()
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Setup Instructions
            if !cloudKitManager.isCloudKitAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Setup Instructions:")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("1. Add PlayerPath.entitlements file to your target")
                    Text("2. In Build Settings, set 'Code Signing Entitlements' to: PlayerPath.entitlements")
                    Text("3. Or add CloudKit capability in Signing & Capabilities")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("CloudKit Test")
    }
}

#Preview {
    NavigationView {
        CloudKitTestView()
    }
}