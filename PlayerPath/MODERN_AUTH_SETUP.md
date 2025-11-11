# Modern iOS Authentication Setup Guide

## Required Info.plist Entries

### 1. Face ID Usage Description
Add this key to your Info.plist:

```xml
<key>NSFaceIDUsageDescription</key>
<string>PlayerPath uses Face ID to securely sign you in quickly without entering your password.</string>
```

## Sign in with Apple Configuration

### 1. Enable Sign in with Apple Capability
1. Open your project in Xcode
2. Select your target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Add "Sign in with Apple"

### 2. Configure Firebase Authentication
1. In Firebase Console, go to Authentication > Sign-in method
2. Enable "Apple" as a sign-in provider
3. Configure your Service ID and Team ID

### 3. Add URL Scheme (for OAuth callbacks)
Your Info.plist should have a URL scheme entry:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>playerpath</string>
            <string>com.googleusercontent.apps.YOUR-CLIENT-ID</string>
        </array>
    </dict>
</array>
```

### 4. Associated Domains (for Universal Links)
If supporting password reset or email verification via universal links:

1. Add "Associated Domains" capability
2. Add your domain: `applinks:playerpath.com`
3. Host an apple-app-site-association file on your server

## Privacy Manifest

### Required Privacy Descriptions
Add these to Info.plist for transparency:

```xml
<!-- User Data Collection -->
<key>NSUserTrackingUsageDescription</key>
<string>PlayerPath uses data to personalize your experience and improve app performance.</string>

<!-- Camera Access (for video recording) -->
<key>NSCameraUsageDescription</key>
<string>PlayerPath needs camera access to record your athletic performance videos.</string>

<!-- Photo Library -->
<key>NSPhotoLibraryUsageDescription</key>
<string>PlayerPath needs access to save videos of your performance.</string>

<!-- Microphone -->
<key>NSMicrophoneUsageDescription</key>
<string>PlayerPath needs microphone access to record audio with your performance videos.</string>
```

## Keychain Access Group (Optional)

If you want to share credentials across apps or extensions:

```xml
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)com.yourcompany.playerpath</string>
</array>
```

## App Transport Security

Ensure you're using HTTPS for all API calls:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
</dict>
```

## Background Modes (if needed)

For features like background uploads:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

## Implementation Checklist

- [ ] Add Face ID usage description
- [ ] Enable Sign in with Apple capability
- [ ] Configure Firebase for Apple authentication
- [ ] Add URL schemes for OAuth
- [ ] Test biometric authentication on physical device
- [ ] Test Sign in with Apple flow
- [ ] Verify Keychain storage is working
- [ ] Test password reset flow
- [ ] Add privacy policy and terms URLs
- [ ] Test all authentication flows in production mode

## Testing Notes

### Biometric Authentication
- **Simulator**: Go to Features > Face ID/Touch ID to simulate
- **Physical Device**: Use actual biometric authentication

### Sign in with Apple
- **Requires**: Real device with Apple ID signed in
- **Sandbox Testing**: Use sandbox Apple IDs for testing

### Keychain
- Keychain data persists across app reinstalls on the same device
- Use "Reset Content and Settings" in simulator to clear
- On device, delete app and reinstall to test fresh install

## Security Best Practices

1. ✅ Store credentials in Keychain, not UserDefaults
2. ✅ Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for biometric data
3. ✅ Never log passwords or tokens
4. ✅ Implement certificate pinning for production
5. ✅ Use Firebase App Check to prevent unauthorized access
6. ✅ Implement rate limiting on authentication endpoints
7. ✅ Enable 2FA for admin/coach accounts

## Common Issues

### Face ID Not Working
- Check Info.plist has `NSFaceIDUsageDescription`
- Verify device has Face ID enrolled in Settings
- Check for proper error handling in authentication flow

### Sign in with Apple Not Appearing
- Verify capability is added in Xcode
- Check Firebase configuration
- Ensure testing on real device with Apple ID

### Keychain Access Denied
- Check keychain access group configuration
- Verify code signing is correct
- Test with proper entitlements file

## Additional Resources

- [Apple Developer: Sign in with Apple](https://developer.apple.com/sign-in-with-apple/)
- [Firebase: Apple Sign-In](https://firebase.google.com/docs/auth/ios/apple)
- [Keychain Services API](https://developer.apple.com/documentation/security/keychain_services)
- [Local Authentication Framework](https://developer.apple.com/documentation/localauthentication)
