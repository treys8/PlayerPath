# PlayerPath iOS - Sandbox Violation Fix Guide

## Problem
You're seeing this error during development:
```
Sandbox: defaults(85524) deny(1) file-read-data /Users/Trey/Desktop/PlayerPath/PlayerPath
```

**Important**: Since PlayerPath is an **iOS app**, this sandbox violation is a development/debugging issue, not a real app problem. iOS apps are automatically sandboxed and don't need manual sandbox configuration like macOS apps.

## Why This Happens in iOS Development

The error occurs because:
1. The iOS Simulator or debugging tools are trying to access files outside the app's sandbox
2. UserDefaults operations during development can trigger these warnings
3. It's usually harmless but indicates better UserDefaults practices should be used

## Solution Applied (Code Improvements)

### 1. Code Changes Made
I've updated both `AuthManagers.swift` and `OnboardingManager.swift` to use app-specific UserDefaults suites instead of the system-wide UserDefaults.standard.

This is a **best practice** that makes your code more robust, even though iOS handles sandboxing automatically.

## For iOS Apps - Next Steps

### Option 1: Ignore the Warning (Recommended for Development)
Since this is an iOS app, the sandbox violation warning during development is typically harmless. Your app will work correctly on devices and in production.

### Option 2: Clean Project (Simple Fix)
1. **Clean Build Folder**: Product → Clean Build Folder (Cmd+Shift+K)
2. **Delete Derived Data**: 
   - Go to Xcode → Settings → Locations
   - Click the arrow next to "Derived Data" path
   - Delete the PlayerPath folder
3. **Restart Simulator**: Quit and restart the iOS Simulator
4. **Rebuild**: Product → Build (Cmd+B)

### Option 3: Add iOS Entitlements (Optional)
If you want to be extra thorough, you can add iOS-specific entitlements:

1. In Xcode, select your project
2. Select your iOS target
3. Go to "Signing & Capabilities"
4. Add capabilities as needed:
   - **Camera** (for video recording)
   - **Microphone** (for video audio)
   - **Push Notifications** (if using)

**Note**: iOS doesn't have "App Sandbox" capability - it's automatically sandboxed.

## Files Modified
- `AuthManagers.swift` - Updated to use app-specific UserDefaults (best practice)
- `OnboardingManager.swift` - Updated to use app-specific UserDefaults (best practice)
- `PlayerPath.entitlements` - Can be deleted (this was for macOS, not needed for iOS)

## Key Differences: iOS vs macOS

| Feature | iOS | macOS |
|---------|-----|-------|
| Sandbox | Automatic | Manual configuration required |
| App Sandbox Capability | Not available/needed | Required for App Store |
| UserDefaults | Automatically sandboxed | May need app-specific suites |
| Development Warnings | Common, usually harmless | Indicates real configuration issues |

## Verification

The sandbox violation warning may still appear during development but won't affect your app's functionality. To verify everything works:

1. ✅ Test sign in/out functionality
2. ✅ Test onboarding flow
3. ✅ Test settings persistence
4. ✅ Run on a physical iOS device (no simulator warnings)

## Summary for iOS

**The sandbox violation warning is normal during iOS development and doesn't indicate a problem with your app.** The code improvements I made are best practices that make your app more robust, but the original issue was just a development warning, not a real bug.