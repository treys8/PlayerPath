# Video Recording Options - Quick Start Guide

## 🚀 5-Minute Integration

### Step 1: Access Settings (Already Done ✅)

The "Video Recording" link has been added to ProfileView.swift:

```swift
NavigationLink(destination: VideoRecordingSettingsView()) {
    Label("Video Recording", systemImage: "video.fill")
}
```

### Step 2: Replace Your Camera (2 minutes)

Find your existing camera implementation and replace:

```swift
// OLD: Simple camera
NativeCameraView(
    videoQuality: .typeHigh,
    onVideoRecorded: { url in
        // handle video
    },
    onCancel: {
        // handle cancel
    }
)

// NEW: Advanced camera with settings
AdvancedCameraView(
    settings: VideoRecordingSettings.shared,
    onVideoRecorded: { url in
        // handle video (same code)
    },
    onCancel: {
        // handle cancel (same code)
    }
)
```

### Step 3: Test (3 minutes)

1. Run app on device (simulator doesn't have camera)
2. Go to Profile → Settings → Video Recording
3. Change quality to 1080p @ 60fps
4. Enable slow-motion
5. Record a test video
6. Verify it works!

Done! ✅

---

## 📋 What You Get

### Immediate Benefits
- ✅ Users can configure video quality
- ✅ Settings persist automatically
- ✅ Slow-motion recording available
- ✅ File size estimates shown
- ✅ Device capabilities detected
- ✅ Professional-grade recordings

### Zero Breaking Changes
- ✅ Existing video code still works
- ✅ Same URLs, same formats
- ✅ Same save/upload flow
- ✅ Same playback behavior

---

## 🎯 Common Use Cases

### Use Case 1: Check Current Settings

```swift
let settings = VideoRecordingSettings.shared
print("Recording at: \(settings.settingsDescription)")
// Output: "Full HD (1080p) • HEVC (H.265) • 60 fps"
```

### Use Case 2: Show Settings Before Recording

```swift
VStack {
    Text("Recording Settings")
        .font(.headline)
    
    Text(VideoRecordingSettings.shared.settingsDescription)
        .font(.caption)
        .foregroundStyle(.secondary)
    
    Text("Est. \(String(format: "%.0f", VideoRecordingSettings.shared.estimatedFileSizePerMinute)) MB/min")
        .font(.caption2)
        .foregroundStyle(.tertiary)
    
    Button("Change Settings") {
        showingSettings = true
    }
    .sheet(isPresented: $showingSettings) {
        VideoRecordingSettingsView()
    }
}
```

### Use Case 3: Warn About Large Files

```swift
let estimatedMB = VideoRecordingSettings.shared.estimatedFileSizePerMinute
if estimatedMB > 100 {
    Text("⚠️ High quality selected. 10 min = \(Int(estimatedMB * 10)) MB")
        .foregroundStyle(.orange)
}
```

### Use Case 4: Check Slow-Motion Availability

```swift
if VideoRecordingSettings.shared.supportsSlowMotion {
    Label("Slow-Motion Available", systemImage: "slowmo")
        .foregroundStyle(.purple)
}
```

---

## ⚙️ Default Settings

If user never changes settings, these defaults apply:

```swift
quality = .high1080p        // Full HD
format = .hevc              // Better compression
frameRate = .fps30          // Standard
slowMotionEnabled = false   // Off
audioEnabled = true         // On
stabilizationMode = .auto   // Automatic
```

**Estimated file size:** ~42 MB per minute

---

## 🔍 Debug Tips

### Print Current Settings

```swift
let s = VideoRecordingSettings.shared
print("""
Settings:
- Quality: \(s.quality.displayName)
- Format: \(s.format.displayName)
- Frame Rate: \(s.frameRate.displayName)
- Slow-Mo: \(s.slowMotionEnabled)
- Audio: \(s.audioEnabled)
- Stabilization: \(s.stabilizationMode.displayName)
- Est. Size: \(s.estimatedFileSizePerMinute) MB/min
""")
```

### Check Device Capabilities

```swift
let settings = VideoRecordingSettings.shared

print("4K Support: \(settings.isQualitySupported(.ultra4K) ? "✅" : "❌")")
print("120fps @ 1080p: \(settings.isFrameRateSupported(.fps120, for: .high1080p) ? "✅" : "❌")")
print("Compatible rates at 4K: \(settings.compatibleFrameRates(for: .ultra4K).map { $0.displayName })")
```

### Reset If Issues

```swift
VideoRecordingSettings.shared.resetToDefaults()
```

---

## 🐛 Troubleshooting

### Problem: Settings not saving
**Solution:** Settings auto-save. Check UserDefaults:
```swift
UserDefaults.standard.dictionaryRepresentation().keys
    .filter { $0.contains("videoRecording") }
    .forEach { print("\($0): \(UserDefaults.standard.object(forKey: $0))") }
```

### Problem: Can't select 4K
**Solution:** Device doesn't support it. Check:
```swift
AVCaptureSession().canSetSessionPreset(.hd4K3840x2160)
```

### Problem: Slow-motion toggle disabled
**Solution:** Need 120+ fps. Increase frame rate first.

### Problem: Videos look wrong
**Solution:** Test on physical device (simulators can't record)

---

## 📱 Testing Checklist

```
Device Testing (Required)
□ Install on physical iPhone/iPad
□ Grant camera permissions
□ Open Profile → Settings → Video Recording
□ Change settings and verify they persist
□ Record test video
□ Check video quality matches settings
□ Test slow-motion if enabled
□ Verify file size is reasonable

Settings Testing
□ All qualities selectable (if supported)
□ Format toggle works
□ Frame rates update
□ Slow-motion follows frame rate rules
□ File size updates with changes
□ Reset to defaults works
□ Settings survive app restart

Camera Testing
□ Recording starts/stops
□ Timer displays correctly
□ Slow-motion indicator shows (if enabled)
□ Camera flip works
□ Cancel stops recording
□ Videos save successfully
```

---

## 💡 Pro Tips

### Tip 1: Recommend Settings to Users
```swift
// Show recommended settings based on use case
Text("Recommended for practice: 720p @ 30fps HEVC")
Text("Recommended for games: 1080p @ 60fps HEVC")
Text("Recommended for slow-motion: 1080p @ 120fps HEVC")
```

### Tip 2: Warn About Storage
```swift
// Check available storage
let fm = FileManager.default
if let attributes = try? fm.attributesOfFileSystem(forPath: NSHomeDirectory()),
   let freeSpace = attributes[.systemFreeSize] as? Int64 {
    let freeGB = Double(freeSpace) / 1_000_000_000
    if freeGB < 2.0 {
        Text("⚠️ Low storage. Consider using 720p.")
    }
}
```

### Tip 3: Auto-Select Quality
```swift
// Auto-select based on available storage
let freeGB = /* calculate free space */
if freeGB < 5 {
    VideoRecordingSettings.shared.quality = .medium720p
} else if freeGB > 20 {
    VideoRecordingSettings.shared.quality = .high1080p
}
```

---

## 📚 Documentation

- **Full Guide**: `VIDEO_RECORDING_OPTIONS_GUIDE.md`
- **Summary**: `VIDEO_RECORDING_OPTIONS_SUMMARY.md`
- **Architecture**: `VIDEO_RECORDING_ARCHITECTURE.md`
- **Integration**: `VideoRecordingIntegrationExample.swift`
- **Complete**: `VIDEO_RECORDING_IMPLEMENTATION_COMPLETE.md`

---

## ✅ That's It!

Your app now has professional video recording options. Users can:
- Choose quality (480p - 4K)
- Select format (HEVC/H.264)
- Pick frame rate (24-240 fps)
- Enable slow-motion
- See file size estimates

And it all "just works" with your existing code! 🎉

---

## 🆘 Need Help?

1. Check the full guide: `VIDEO_RECORDING_OPTIONS_GUIDE.md`
2. Review examples: `VideoRecordingIntegrationExample.swift`
3. Test on physical device (not simulator)
4. Check console for debug logs
5. Verify camera permissions granted

**Most Common Issue:** Testing on simulator (camera needs real device)

---

**Quick Start Complete!** 🚀

You're ready to give users professional-grade video recording control!
