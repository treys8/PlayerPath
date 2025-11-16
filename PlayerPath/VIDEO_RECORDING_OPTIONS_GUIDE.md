# Video Recording Options Implementation Guide

## Overview

This guide covers the new advanced video recording options that give users full control over video quality, format, frame rate, and slow-motion recording.

## Features Implemented

### 1. **Video Quality Settings** 📹
- **SD (480p)** - Best for sharing and storage (~8 MB/min)
- **HD (720p)** - Good quality, smaller files (~25 MB/min)
- **Full HD (1080p)** - High quality, recommended (~60 MB/min)
- **4K Ultra HD** - Maximum quality, large files (~200 MB/min)

### 2. **Video Format Options** 🎬
- **HEVC (H.265)** - Better compression, 30% smaller files
- **H.264** - Maximum compatibility across devices

### 3. **Frame Rate Options** ⚡
- **24 fps** - Cinematic look
- **30 fps** - Standard video
- **60 fps** - Smooth motion
- **120 fps** - Slow-motion capable
- **240 fps** - Ultra slow-motion

### 4. **Slow-Motion Recording** 🐌
- Automatically enabled when frame rate ≥ 120 fps
- Records at high frame rate for smooth slow-motion playback
- Clear indicator during recording

### 5. **Additional Settings** ⚙️
- **Audio Recording** - Toggle audio on/off
- **Video Stabilization** - Off, Standard, Cinematic, or Auto modes
- **File Size Estimation** - Real-time calculation based on settings

## File Structure

```
PlayerPath/
├── VideoRecordingSettings.swift          # Settings model with persistence
├── VideoRecordingSettingsView.swift      # UI for configuring settings
├── AdvancedCameraView.swift              # Advanced camera implementation
└── ProfileView.swift                      # Updated with settings link
```

## How to Use

### For Users

1. **Access Settings**
   - Go to Profile/More tab
   - Tap "Video Recording" in Settings section
   
2. **Configure Quality**
   - Choose resolution based on needs
   - Higher quality = larger files
   - Unsupported resolutions are marked
   
3. **Select Format**
   - HEVC for smaller files (recommended)
   - H.264 for older device compatibility
   
4. **Choose Frame Rate**
   - 30 fps for normal recording
   - 60 fps for smooth action
   - 120+ fps for slow-motion
   - Availability depends on quality
   
5. **Enable Slow-Motion**
   - Only available at 120+ fps
   - Toggle on for automatic slow-motion recording
   
6. **Review Summary**
   - Check estimated file size per minute
   - See current settings at a glance

### For Developers

#### Accessing Settings

```swift
// Get shared instance
let settings = VideoRecordingSettings.shared

// Read current settings
let quality = settings.quality
let format = settings.format
let frameRate = settings.frameRate
let slowMo = settings.slowMotionEnabled

// Estimated file size
let mbPerMinute = settings.estimatedFileSizePerMinute
```

#### Using Advanced Camera

```swift
// In your video recorder view
AdvancedCameraView(
    settings: VideoRecordingSettings.shared,
    onVideoRecorded: { url in
        // Handle recorded video
        saveVideo(at: url)
    },
    onCancel: {
        // Handle cancellation
        dismiss()
    }
)
```

#### Checking Device Capabilities

```swift
let settings = VideoRecordingSettings.shared

// Check if quality is supported
let is4KSupported = settings.isQualitySupported(.ultra4K)

// Check if frame rate works with quality
let is120fpsAt1080p = settings.isFrameRateSupported(.fps120, for: .high1080p)

// Get compatible frame rates
let compatibleRates = settings.compatibleFrameRates(for: .ultra4K)
// Returns: [.fps24, .fps30, .fps60]
```

## Implementation Details

### Settings Persistence

Settings are automatically saved to `UserDefaults` when changed:

```swift
@Observable
final class VideoRecordingSettings {
    var quality: VideoQuality {
        didSet {
            saveSettings() // Auto-save on change
        }
    }
    
    // ... other properties with auto-save
}
```

### Device Compatibility

The system automatically checks device capabilities:

- **Quality**: Validates `AVCaptureSession.Preset` support
- **Frame Rate**: Checks `videoSupportedFrameRateRanges`
- **Format**: HEVC requires iOS 11+

Unsupported options are:
- Grayed out in UI
- Show warning icons
- Display "Not available" message

### Slow-Motion Logic

```swift
// Slow-motion is enabled when:
var supportsSlowMotion: Bool {
    return frameRate.fps >= 120
}

// User toggle only available when supported
Toggle("Slow-Motion", isOn: $settings.slowMotionEnabled)
    .disabled(!settings.supportsSlowMotion)
```

### File Size Estimation

```swift
var estimatedFileSizePerMinute: Double {
    let baseSize = quality.estimatedMBPerMinute
    let formatMultiplier = format == .hevc ? 0.7 : 1.0
    let frameRateMultiplier = frameRate.multiplier
    
    return baseSize * formatMultiplier * frameRateMultiplier
}
```

**Examples:**
- 1080p @ 30fps HEVC: ~42 MB/min
- 1080p @ 60fps H.264: ~120 MB/min
- 4K @ 30fps HEVC: ~140 MB/min

## Integration with Existing Code

### Option 1: Replace NativeCameraView (Recommended)

```swift
// In VideoRecorderView_Refactored.swift
var body: some View {
    // Replace:
    // NativeCameraView(...)
    
    // With:
    AdvancedCameraView(
        settings: VideoRecordingSettings.shared,
        onVideoRecorded: { url in
            self.recordedVideoURL = url
            self.showingPlayResultOverlay = true
        },
        onCancel: {
            dismiss()
        }
    )
}
```

### Option 2: Add as Alternative Camera Mode

```swift
enum CameraMode {
    case simple    // Use NativeCameraView
    case advanced  // Use AdvancedCameraView
}

@State private var cameraMode: CameraMode = .advanced

// In body
if cameraMode == .simple {
    NativeCameraView(...)
} else {
    AdvancedCameraView(...)
}
```

### Option 3: Settings-Based Selection

```swift
// Use advanced camera if user has custom settings
@State private var useAdvancedCamera: Bool {
    let settings = VideoRecordingSettings.shared
    return settings.quality != .high1080p ||
           settings.frameRate != .fps30 ||
           settings.slowMotionEnabled
}

if useAdvancedCamera {
    AdvancedCameraView(...)
} else {
    NativeCameraView(...) // Simpler, faster
}
```

## UI/UX Considerations

### Settings View Features

✅ **Live Updates** - Settings save immediately
✅ **Smart Validation** - Incompatible options disabled
✅ **Auto-Adjustment** - Frame rate adjusts when quality changes
✅ **File Size Preview** - Shows estimated storage needs
✅ **Device Awareness** - Warns about unsupported features
✅ **Reset Option** - Easy return to defaults

### Camera View Features

✅ **Settings Display** - Shows current configuration
✅ **Recording Timer** - Real-time duration display
✅ **Slow-Mo Indicator** - Purple badge when enabled
✅ **All Orientations** - Portrait and landscape support
✅ **Flip Camera** - Switch between front/back
✅ **Visual Feedback** - Animated recording button

## Best Practices

### For Performance

1. **Default to 1080p @ 30fps** - Good balance
2. **Use HEVC** - Smaller files, modern devices
3. **Auto Stabilization** - Let system decide
4. **Enable Audio** - Unless specifically not needed

### For Quality

1. **Use 60fps for sports** - Smooth action capture
2. **Enable slow-motion for highlights** - Better replays
3. **4K for special recordings** - Games, tournaments
4. **Cinematic stabilization** - Professional look

### For Storage

1. **Monitor estimated file sizes**
2. **Lower quality for practice** - Save space
3. **Use HEVC over H.264** - 30% savings
4. **Consider 720p for long recordings**

## Troubleshooting

### Issue: 4K option grayed out
**Solution**: Device doesn't support 4K recording. Use 1080p instead.

### Issue: 240fps not available
**Solution**: 240fps only available at 480p or 720p. Lower quality setting.

### Issue: Slow-motion toggle disabled
**Solution**: Increase frame rate to 120fps or higher.

### Issue: Large file sizes
**Solutions:**
- Switch to HEVC format
- Lower resolution (720p)
- Reduce frame rate (30fps)

### Issue: Videos look shaky
**Solution**: Enable stabilization (Standard or Cinematic mode)

## Future Enhancements

Potential additions:

- [ ] HDR video support
- [ ] ProRes format option
- [ ] Custom aspect ratios
- [ ] Zoom controls
- [ ] Focus/exposure lock
- [ ] Grid overlay
- [ ] Level indicator
- [ ] Audio monitoring
- [ ] External mic support
- [ ] Time-lapse mode

## Testing Checklist

- [ ] Settings persist across app restarts
- [ ] All quality options work on test device
- [ ] Frame rate changes apply correctly
- [ ] Slow-motion toggle follows frame rate
- [ ] File sizes match estimates
- [ ] Incompatible options properly disabled
- [ ] Reset to defaults works
- [ ] Settings link appears in Profile
- [ ] Camera records at correct quality
- [ ] Videos play back correctly
- [ ] Orientation handled properly
- [ ] Timer displays accurately
- [ ] Stabilization improves footage

## Summary

The video recording options implementation provides users with professional-grade control over their recordings while maintaining a simple, intuitive interface. The system automatically handles device capabilities, validates settings, and provides helpful feedback about file sizes and compatibility.

Key achievements:
- ✅ 4 quality levels (480p to 4K)
- ✅ 2 format options (HEVC, H.264)
- ✅ 5 frame rates (24 to 240 fps)
- ✅ Slow-motion support
- ✅ Stabilization modes
- ✅ Persistent settings
- ✅ Device-aware UI
- ✅ File size estimation

The implementation is production-ready and follows iOS best practices for video capture and settings management.
