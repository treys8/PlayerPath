//
//  ErrorHandlingDemoView.swift
//  PlayerPath
//
//  Demo view showing how to integrate the new error handling system
//

import SwiftUI

struct ErrorHandlingDemoView: View {
    @StateObject private var errorHandler = ErrorHandlerService()
    @StateObject private var videoUploadService = VideoUploadService()
    @StateObject private var authManager = ComprehensiveAuthManager()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Error Handling Demo")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                VStack(spacing: 15) {
                    // Demo buttons to trigger different types of errors
                    Button("Test Network Error") {
                        let error = PlayerPathError.networkUnavailable
                        errorHandler.handle(error, context: "Demo network test")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Test Video Upload Error") {
                        let error = PlayerPathError.videoUploadFailed(reason: "Connection timeout")
                        errorHandler.handle(error, context: "Demo video upload", canRetry: true) {
                            print("Retrying video upload...")
                            // Simulate retry logic
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Test CloudKit Error") {
                        let error = PlayerPathError.cloudKitNotSignedIn
                        errorHandler.handle(error, context: "Demo CloudKit sync")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Test Authentication Error") {
                        let error = PlayerPathError.invalidCredentials
                        errorHandler.handle(error, context: "Demo sign in")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Divider()
                
                // Show integration with existing services
                VStack(alignment: .leading, spacing: 10) {
                    Text("Service Integration Examples:")
                        .font(.headline)
                    
                    Text("• VideoUploadService now uses ErrorHandlerService")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("• AuthManager uses PlayerPathError for consistent errors")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("• CloudKitManager categorizes errors properly")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Error history section
                if !errorHandler.errorHistory.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Recent Errors:")
                            .font(.headline)
                        
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(errorHandler.errorHistory.prefix(5)) { entry in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                                .font(.caption)
                                            Text(entry.formattedTimestamp)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                        }
                                        
                                        Text(entry.error.localizedDescription)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                        
                                        if !entry.context.isEmpty {
                                            Text("Context: \(entry.context)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear History") {
                        errorHandler.clearErrorHistory()
                    }
                    .disabled(errorHandler.errorHistory.isEmpty)
                }
            }
        }
        .errorHandling(errorHandler) // Apply the error handling modifier
    }
}

// MARK: - Integration Examples

/// Example of how to update an existing view to use error handling
struct VideoRecorderViewUpdated: View {
    @StateObject private var videoUploadService = VideoUploadService()
    @State private var showingPhotoPicker = false
    
    var body: some View {
        VStack {
            Button("Upload Video") {
                showingPhotoPicker = true
            }
            .buttonStyle(.borderedProminent)
            
            if videoUploadService.isProcessingVideo {
                ProgressView("Processing video...")
                    .padding()
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: .constant(nil),
            matching: .videos
        )
        // Apply error handling - this will show alerts automatically
        .errorHandling(videoUploadService.errorHandler)
    }
}

/// Example of how to handle errors in a service method
extension VideoUploadService {
    func demonstrateErrorHandlingPattern() async {
        // Example 1: Handle with automatic retry
        let result = await errorHandler.withErrorHandling(
            context: "Video compression",
            canRetry: true
        ) {
            // Simulate operation that might fail
            if Bool.random() {
                throw PlayerPathError.videoCompressionFailed(reason: "Insufficient memory")
            }
            return "Success"
        }
        
        switch result {
        case .success(let message):
            print("Operation succeeded: \(message)")
        case .failure(let error):
            print("Operation failed: \(error)")
        }
        
        // Example 2: Handle with manual error management
        do {
            // Some operation that might fail
            throw PlayerPathError.videoFileTooLarge(size: 200_000_000, maxSize: 100_000_000)
        } catch {
            errorHandler.handle(
                error,
                context: "File size validation",
                canRetry: false
            )
        }
    }
}

#Preview {
    ErrorHandlingDemoView()
}