//
//  CloudKitTestView.swift
//  PlayerPath
//
//  Created by Assistant on 10/29/25.
//

import SwiftUI

struct CloudKitTestView: View {
    @StateObject private var cloudKitManager = CloudKitManager()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("CloudKit Status Test")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: cloudKitManager.isSignedInToiCloud ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(cloudKitManager.isSignedInToiCloud ? .green : .red)
                    
                    Text("iCloud Status: \(cloudKitManager.isSignedInToiCloud ? "Connected" : "Not Available")")
                }
                
                if let error = cloudKitManager.cloudKitError, !error.isEmpty {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                }
            }
            
            Button("Recheck iCloud Status") {
                cloudKitManager.checkiCloudStatus()
            }
            .buttonStyle(.bordered)
            
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