//
//  ProfileImageManager.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/28/25.
//

import Foundation
import UIKit
import SwiftUI
import os

class ProfileImageManager {
    static let shared = ProfileImageManager()
    
    private init() {}
    
    private let log = Logger(subsystem: "com.playerpath.app", category: "ProfileImageManager")
    private let cache = NSCache<NSString, UIImage>()
    
    // Directory for storing profile images
    private var profileImagesDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let profileDir = documentsPath.appendingPathComponent("ProfileImages")
        if !FileManager.default.fileExists(atPath: profileDir.path) {
            do {
                try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
            } catch {
                log.error("Failed to create profile images directory: \(error.localizedDescription)")
            }
        }
        return profileDir
    }
    
    private func normalizedImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized ?? image
    }
    
    // Save profile image and return file path
    func saveProfileImage(_ image: UIImage, for userID: UUID) -> String? {
        guard let imageData = normalizedImage(image).jpegData(compressionQuality: 0.8) else {
            log.error("Failed to convert image to JPEG data")
            return nil
        }
        let fileName = "\(userID.uuidString)_profile.jpg"
        let targetURL = profileImagesDirectory.appendingPathComponent(fileName)
        let tempURL = profileImagesDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
        do {
            try imageData.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: targetURL)
            log.debug("Profile image saved to: \(targetURL.path)")
            // Update cache
            if let img = UIImage(contentsOfFile: targetURL.path) {
                cache.setObject(img, forKey: targetURL.path as NSString)
            }
            return targetURL.path
        } catch {
            log.error("Failed to save profile image: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
    }
    
    // Load profile image from file path
    func loadProfileImage(from path: String?) -> UIImage? {
        guard let path = path, !path.isEmpty else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        if FileManager.default.fileExists(atPath: path), let image = UIImage(contentsOfFile: path) {
            cache.setObject(image, forKey: path as NSString)
            return image
        }
        return nil
    }
    
    // Delete profile image file
    func deleteProfileImage(at path: String?) {
        guard let path = path, !path.isEmpty else { return }
        if FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(atPath: path)
                cache.removeObject(forKey: path as NSString)
                log.debug("Deleted profile image at: \(path)")
            } catch {
                log.error("Failed to delete profile image: \(error.localizedDescription)")
            }
        }
    }
    
    enum ResizeMode { case aspectFit, aspectFill }
    
    // Create a resized version of the image for better performance
    func resizeImage(_ image: UIImage, to size: CGSize, mode: ResizeMode = .aspectFill) -> UIImage {
        let scale: CGFloat = (mode == .aspectFill)
            ? max(size.width / image.size.width, size.height / image.size.height)
            : min(size.width / image.size.width, size.height / image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let origin = CGPoint(x: (size.width - newSize.width) / 2, y: (size.height - newSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: newSize))
        }
    }
    
    func saveProfileImageAsync(_ image: UIImage, for userID: UUID) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let path = self.saveProfileImage(image, for: userID)
                continuation.resume(returning: path)
            }
        }
    }
    
    func loadProfileImageAsync(from path: String?) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = self.loadProfileImage(from: path)
                continuation.resume(returning: image)
            }
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
            let image = await ProfileImageManager.shared.loadProfileImageAsync(from: user.profileImagePath)
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
        .disabled(isLoading)
        .onAppear {
            loadProfileImage()
        }
        .confirmationDialog("Change Profile Picture", isPresented: $showingActionSheet) {
            Button("Take Photo") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    imageSourceType = .camera
                } else {
                    imageSourceType = .photoLibrary
                }
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
            let image = await ProfileImageManager.shared.loadProfileImageAsync(from: user.profileImagePath)
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
            
            // Save new image asynchronously
            if let newPath = await ProfileImageManager.shared.saveProfileImageAsync(resizedImage, for: user.id) {
                await MainActor.run {
                    user.profileImagePath = newPath
                    profileImage = resizedImage
                    isLoading = false
                    onImageUpdated()
                }
            } else {
                await MainActor.run { isLoading = false }
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

