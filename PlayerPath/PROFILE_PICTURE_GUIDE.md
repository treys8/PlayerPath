# Profile Picture Feature Guide

This guide explains the new profile picture functionality added to PlayerPath.

## What's New

Users can now set and edit their profile pictures throughout the app. The profile image system includes:

- **Editable Profile Pictures**: Tap to change your profile picture
- **Multiple Sources**: Choose from camera or photo library
- **Automatic Resizing**: Images are optimized for performance
- **File Management**: Images are stored locally and managed automatically

## Features

### Profile Image Display
- **ProfileImageView**: A read-only view that displays the user's profile picture
- **Fallback Design**: Shows a default person icon when no image is set
- **Consistent Sizing**: Adapts to different sizes throughout the app
- **Loading States**: Shows progress indicator while loading images

### Profile Image Editing
- **EditableProfileImageView**: Allows users to change their profile picture
- **Action Sheet**: Provides options to take a photo, choose from library, or remove current photo
- **Edit Indicator**: Shows a pencil icon to indicate the image is editable
- **Immediate Updates**: Changes are reflected instantly across the app

## Implementation Details

### File Storage
- Images are stored in the app's Documents directory under `ProfileImages/`
- Each user's image is named with their UUID: `{userID}_profile.jpg`
- Images are compressed to 80% JPEG quality for optimal file size
- Automatic cleanup when images are replaced or removed

### Image Processing
- Images are resized to 300x300 pixels for optimal performance
- Aspect ratio is preserved with proper cropping
- Images are processed on background threads to avoid UI blocking

### Data Model Updates
- Added `profileImagePath: String?` to the User model
- Path is stored in SwiftData and automatically persisted
- Changes trigger UI updates through SwiftUI's observation system

## Usage in Code

### Display Only (ProfileImageView)
```swift
ProfileImageView(user: user, size: 50)
```

### Editable (EditableProfileImageView)
```swift
EditableProfileImageView(user: user, size: 80) {
    // Called when image is updated
    try? modelContext.save()
}
```

### Custom Implementation
```swift
// Load image manually
let image = ProfileImageManager.shared.loadProfileImage(from: user.profileImagePath)

// Save new image
let imagePath = ProfileImageManager.shared.saveProfileImage(newImage, for: user.id)
user.profileImagePath = imagePath
```

## Privacy Requirements

Make sure your Info.plist includes these privacy descriptions:

```xml
<!-- Camera access for taking profile photos -->
<key>NSCameraUsageDescription</key>
<string>PlayerPath needs camera access to record videos of your athletic performance and take profile pictures.</string>

<!-- Photo library access for choosing profile photos -->
<key>NSPhotoLibraryUsageDescription</key>
<string>PlayerPath needs photo library access to allow you to upload existing videos and choose profile pictures.</string>
```

## Where Profile Pictures Appear

1. **Profile Tab**: Main profile view with large, editable profile picture
2. **Edit Account**: Dedicated profile picture editing in account settings
3. **Navigation**: Could be added to navigation bars or headers
4. **Comments/Social**: Ready for future social features

## Benefits

- **Personalization**: Users can customize their profile appearance
- **Professional Look**: Gives the app a more polished, social feel
- **User Engagement**: Encourages users to complete their profile
- **Recognition**: Makes it easier to identify different user profiles
- **Future Ready**: Foundation for social features and multi-user support

## Error Handling

The system gracefully handles:
- **Missing Files**: Falls back to default icon if image file is deleted
- **Corrupted Images**: Shows loading state and falls back to default
- **Permission Denied**: Handles camera/photo library permission denials
- **Storage Issues**: Manages disk space and file system errors

## Performance Considerations

- **Lazy Loading**: Images are loaded asynchronously on background threads
- **Memory Management**: Images are resized and cached appropriately  
- **File Size**: JPEG compression balances quality and storage
- **UI Responsiveness**: All image operations are performed off the main thread

The profile picture system is designed to be lightweight, user-friendly, and easily extensible for future enhancements.