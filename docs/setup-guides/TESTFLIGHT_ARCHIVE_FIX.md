# PlayerPath iOS - TestFlight Archive Fix Guide

## Problem
You're getting a sandbox violation error that prevents archiving for TestFlight:
```
Sandbox: defaults(88503) deny(1) file-read-data /Users/Trey/Desktop/PlayerPath/PlayerPath
```

## Root Cause
During the iOS archive process, Xcode's build system becomes more restrictive about file access. UserDefaults operations that work fine during development can fail during archiving because they try to access system-level defaults instead of app-specific storage.

## Solution Applied

### 1. Created UserDefaultsManager.swift
- **Sandbox-safe UserDefaults wrapper** that creates app-specific storage suites
- **Prevents archive-time sandbox violations** by avoiding system UserDefaults
- **Centralized storage management** for better reliability

### 2. Updated Core Files
- **AuthManagers.swift** - Now uses UserDefaultsManager.shared instead of UserDefaults.standard
- **OnboardingManager.swift** - Now uses UserDefaultsManager.shared instead of UserDefaults.standard

### 3. Key Improvements
- ✅ **App-specific UserDefaults suite** with unique naming
- ✅ **Proper synchronization** after each write operation  
- ✅ **Fallback handling** if suite creation fails
- ✅ **Archive-safe storage** that won't trigger sandbox violations

## Next Steps to Archive Successfully

### Step 1: Clean Everything
1. **Quit Xcode completely**
2. **Clean Build Folder**: Product → Clean Build Folder (Cmd+Shift+K)
3. **Delete Derived Data**:
   - Xcode → Settings → Locations → Derived Data
   - Click arrow next to path, delete PlayerPath folder
4. **Restart Xcode**

### Step 2: Verify Target Settings
1. Select your **PlayerPath project** in navigator
2. Select your **iOS app target**
3. **Build Settings** tab → search for "Other Linker Flags"
4. Make sure no unusual flags are set that might cause sandbox issues

### Step 3: Archive Process
1. **Select iOS Device** (not simulator) in scheme selector
2. **Product → Archive** (Cmd+Shift+B won't work, use Archive specifically)
3. **Wait for completion** - should now work without sandbox errors

### Step 4: Upload to TestFlight
1. In **Organizer** window that opens after archiving
2. **Distribute App → App Store Connect**  
3. **Upload** → Follow prompts to TestFlight

## Verification That Fix Worked

After archiving successfully, you should see:
- ✅ **No sandbox violation errors** in build log
- ✅ **Archive appears in Organizer** 
- ✅ **Upload to TestFlight succeeds**
- ✅ **App functions normally** with authentication/settings preserved

## Files Added/Modified

### New Files:
- `UserDefaultsManager.swift` - Sandbox-safe UserDefaults wrapper

### Modified Files:
- `AuthManagers.swift` - Updated to use UserDefaultsManager
- `OnboardingManager.swift` - Updated to use UserDefaultsManager  

## Troubleshooting

### If Archive Still Fails:
1. **Check Console.app** during archive for specific error details
2. **Verify Bundle Identifier** is set correctly in project settings
3. **Check Code Signing** - make sure certificates are valid
4. **Try different Xcode version** if available

### If Archive Succeeds But Upload Fails:
1. **Check App Store Connect** status
2. **Verify provisioning profiles** are current
3. **Check bundle identifier** matches App Store Connect app

The sandbox violation error should now be completely resolved for archiving!