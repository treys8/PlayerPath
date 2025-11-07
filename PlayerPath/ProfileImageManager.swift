//
//  ProfileImageManager.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/28/25.
//

import Foundation
import UIKit
import SwiftUI

class ProfileImageManager {
    static let shared = ProfileImageManager()
    
    private init() {}
    
    // Directory for storing profile images
    private var profileImagesDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let profileDir = documentsPath.appendingPathComponent("ProfileImages")
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: profileDir.path) {
            try? FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        }
        
        return profileDir
    }
    
    // Save profile image and return file path
    func saveProfileImage(_ image: UIImage, for userID: UUID) -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("Failed to convert image to data")
            return nil
        }
        
        let fileName = "\(userID.uuidString)_profile.jpg"
        let fileURL = profileImagesDirectory.appendingPathComponent(fileName)
        
        do {
            try imageData.write(to: fileURL)
            print("Profile image saved to: \(fileURL.path)")
            return fileURL.path
        } catch {
            print("Failed to save profile image: \(error)")
            return nil
        }
    }
    
    // Load profile image from file path
    func loadProfileImage(from path: String?) -> UIImage? {
        guard let path = path, !path.isEmpty else { return nil }
        
        if FileManager.default.fileExists(atPath: path) {
            return UIImage(contentsOfFile: path)
        }
        
        return nil
    }
    
    // Delete profile image file
    func deleteProfileImage(at path: String?) {
        guard let path = path, !path.isEmpty else { return }
        
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
            print("Deleted profile image at: \(path)")
        }
    }
    
    // Create a resized version of the image for better performance
    func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Profile Image View Components

struct ProfileImageView: View {
    let user: User
    let size: CGFloat
    @State private var profileImage: UIImage?
    @State private var isLoading = false
    
    init(user: User, size: CGFloat = 50) {
        self.user = user
        self.size = size
    }
    
    var body: some View {
        Group {
            if let image = profileImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: size, height: size)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: size * 0.4))
                                    .foregroundColor(.blue)
                            }
                        }
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            }
        }
        .onAppear {
            loadProfileImage()
        }
        .onChange(of: user.profileImagePath) { _, _ in
            loadProfileImage()
        }
    }
    
    private func loadProfileImage() {
        isLoading = true
        
        Task {
            let image = await loadImageAsync()
            await MainActor.run {
                profileImage = image
                isLoading = false
            }
        }
    }
    
    private func loadImageAsync() async -> UIImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = ProfileImageManager.shared.loadProfileImage(from: user.profileImagePath)
                continuation.resume(returning: image)
            }
        }
    }
}

struct EditableProfileImageView: View {
    let user: User
    let size: CGFloat
    let onImageUpdated: () -> Void
    
    @State private var profileImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingActionSheet = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var isLoading = false
    
    init(user: User, size: CGFloat = 100, onImageUpdated: @escaping () -> Void = {}) {
        self.user = user
        self.size = size
        self.onImageUpdated = onImageUpdated
    }
    
    var body: some View {
        Button(action: { showingActionSheet = true }) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image = profileImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color(.systemGray4), lineWidth: 2)
                            )
                    } else {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: size, height: size)
                            .overlay(
                                Group {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: size * 0.4))
                                            .foregroundColor(.blue)
                                    }
                                }
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color(.systemGray4), lineWidth: 2)
                            )
                    }
                }
                
                // Edit button overlay
                Circle()
                    .fill(Color.blue)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay(
                        Image(systemName: "pencil")
                            .font(.system(size: size * 0.12))
                            .foregroundColor(.white)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadProfileImage()
        }
        .confirmationDialog("Change Profile Picture", isPresented: $showingActionSheet) {
            Button("Take Photo") {
                imageSourceType = .camera
                showingImagePicker = true
            }
            
            Button("Choose from Library") {
                imageSourceType = .photoLibrary
                showingImagePicker = true
            }
            
            if user.profileImagePath != nil {
                Button("Remove Current Photo", role: .destructive) {
                    removeProfileImage()
                }
            }
            
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(sourceType: imageSourceType) { image in
                saveProfileImage(image)
            }
        }
    }
    
    private func loadProfileImage() {
        isLoading = true
        
        Task {
            let image = await loadImageAsync()
            await MainActor.run {
                profileImage = image
                isLoading = false
            }
        }
    }
    
    private func loadImageAsync() async -> UIImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = ProfileImageManager.shared.loadProfileImage(from: user.profileImagePath)
                continuation.resume(returning: image)
            }
        }
    }
    
    private func saveProfileImage(_ image: UIImage) {
        isLoading = true
        
        Task {
            // Delete old image if it exists
            if let oldPath = user.profileImagePath {
                ProfileImageManager.shared.deleteProfileImage(at: oldPath)
            }
            
            // Resize image for better performance
            let resizedImage = ProfileImageManager.shared.resizeImage(image, to: CGSize(width: 300, height: 300))
            
            // Save new image
            if let newPath = ProfileImageManager.shared.saveProfileImage(resizedImage, for: user.id) {
                await MainActor.run {
                    user.profileImagePath = newPath
                    profileImage = resizedImage
                    isLoading = false
                    onImageUpdated()
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func removeProfileImage() {
        if let path = user.profileImagePath {
            ProfileImageManager.shared.deleteProfileImage(at: path)
            user.profileImagePath = nil
            profileImage = nil
            onImageUpdated()
        }
    }
}

// MARK: - UIImagePickerController Wrapper

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.onImagePicked(editedImage)
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.onImagePicked(originalImage)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}