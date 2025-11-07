# Firebase Setup Guide for PlayerPath

## Step 1: Create Firebase Project

1. Go to https://console.firebase.google.com
2. Click "Create a project"
3. Name it "PlayerPath" (or whatever you prefer)
4. Disable Google Analytics (optional for this demo)
5. Click "Create project"

## Step 2: Add iOS App

1. Click "Add app" → iOS
2. Enter your bundle identifier: 
   - Check your Xcode project settings
   - Usually something like `com.yourname.PlayerPath`
3. Enter app nickname: "PlayerPath iOS"
4. Leave App Store ID blank for now
5. Click "Register app"

## Step 3: Download Configuration File

1. Download `GoogleService-Info.plist`
2. Drag it into your Xcode project
3. Make sure "Add to target" is checked for your main app target
4. Make sure it's in the root of your project (same level as other Swift files)

## Step 4: Enable Email/Password Authentication

1. In Firebase Console, go to "Authentication"
2. Click "Get started"
3. Go to "Sign-in method" tab
4. Click "Email/Password"
5. Enable the first toggle (Email/Password)
6. Click "Save"

## Step 5: Test in iOS Simulator

1. Build and run your app
2. Try to create a new account with email/password
3. Check Xcode console for any error messages

## Common Issues:

- **Bundle ID mismatch**: Make sure the bundle ID in Firebase matches your Xcode project
- **File not in target**: Make sure GoogleService-Info.plist is added to your app target
- **Authentication not enabled**: Make sure Email/Password is enabled in Firebase Console

## Verification:

When properly set up, you should see in Xcode console:
```
✅ Firebase is configured
```

Instead of:
```
❌ Firebase is NOT configured!
```