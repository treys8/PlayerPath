# PlayerPath - Sandbox Violation Fix Guide

## Problem
You're seeing this error:
```
Sandbox: defaults(81784) deny(1) file-read-data /Users/Trey/Desktop/PlayerPath/PlayerPath
```

This occurs because your app is trying to access UserDefaults in a way that violates macOS sandbox restrictions.

## Solution Applied

### 1. Code Changes Made
I've updated both `AuthManagers.swift` and `OnboardingManager.swift` to use app-specific UserDefaults suites instead of the system-wide UserDefaults.standard.

### 2. Entitlements File Created
Created `PlayerPath.entitlements` with proper sandbox permissions for:
- App sandbox enabled
- Camera access
- Microphone access
- File access for pictures and movies
- Network client access

### 3. Next Steps - Configure Your Xcode Project

#### Step 1: Add Entitlements File to Project
1. In Xcode, select your PlayerPath project in the navigator
2. Select your app target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability" and add "App Sandbox" if not already present
5. In the "Build Settings" tab, search for "Code Signing Entitlements"
6. Set the value to `PlayerPath.entitlements`

#### Step 2: Configure App Sandbox Settings
In the "Signing & Capabilities" tab under "App Sandbox":
- ✅ Enable "App Sandbox"
- ✅ Enable "Outgoing Connections (Client)"
- ✅ Enable "Camera" under Hardware
- ✅ Enable "Audio Input" under Hardware
- ✅ Enable "Movies" under File System
- ✅ Enable "Pictures" under File System

#### Step 3: Clean and Rebuild
1. Product → Clean Build Folder (Cmd+Shift+K)
2. Product → Build (Cmd+B)

### 4. Alternative Solution (If Above Doesn't Work)

If you're still getting sandbox violations, you can disable the sandbox temporarily for development:

1. In your `PlayerPath.entitlements`, change:
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

2. Or remove the App Sandbox capability entirely from "Signing & Capabilities"

### 5. Verification

After implementing the fix:
1. Run your app
2. Check Console.app for any remaining sandbox violations
3. Test UserDefaults functionality (sign in/out, onboarding settings)

### 6. Production Considerations

- For Mac App Store distribution, you MUST have sandboxing enabled
- For direct distribution, sandboxing is optional but recommended
- All UserDefaults operations now use app-specific containers, which is safer

## Files Modified
- `AuthManagers.swift` - Updated to use app-specific UserDefaults
- `OnboardingManager.swift` - Updated to use app-specific UserDefaults  
- `PlayerPath.entitlements` - Created with proper sandbox permissions

The sandbox violation should now be resolved!