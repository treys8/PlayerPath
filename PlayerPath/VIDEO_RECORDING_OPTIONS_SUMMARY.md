# Video Recording Options - Quick Reference

## 🎯 What's New

Users can now customize video recording with:
- **Quality**: 480p, 720p, 1080p, 4K
- **Format**: HEVC or H.264
- **Frame Rate**: 24, 30, 60, 120, 240 fps
- **Slow-Motion**: Available at 120+ fps
- **Stabilization**: Off, Standard, Cinematic, Auto

## 📁 New Files Created

1. **VideoRecordingSettings.swift** - Settings model with persistence
2. **VideoRecordingSettingsView.swift** - Settings UI
3. **AdvancedCameraView.swift** - Camera with full control
4. **VIDEO_RECORDING_OPTIONS_GUIDE.md** - Complete documentation

## 🔧 Modified Files

- **ProfileView.swift** - Added "Video Recording" link in Settings section

## ⚡ Quick Integration

### Add to your video recorder:

```swift
// Replace NativeCameraView with:
AdvancedCameraView(
    settings: VideoRecordingSettings.shared,
    onVideoRecorded: { url in
        // Handle video
    },
    onCancel: {
        // Handle cancel
    }
)
```

### Access settings anywhere:

```swift
let settings = VideoRecordingSettings.shared
print("Current: \(settings.settingsDescription)")
print("Est. size: \(settings.estimatedFileSizePerMinute) MB/min")
```

## 🎨 User Experience

### Settings Flow
1. User opens Profile → Settings → Video Recording
2. Selects quality, format, frame rate
3. Optionally enables slow-motion (if 120+ fps)
4. Sees estimated file size per minute
5. Settings auto-save immediately

### Recording Flow
1. Camera opens with current settings displayed
2. Optional slow-motion indicator shown
3. Records with selected quality/frame rate
4. Videos automatically use chosen format

## 📊 File Size Examples

| Quality | Frame Rate | Format | Est. Size/Min |
|---------|------------|--------|---------------|
| 1080p   | 30 fps     | HEVC   | ~42 MB        |
| 1080p   | 60 fps     | HEVC   | ~84 MB        |
| 1080p   | 120 fps    | HEVC   | ~168 MB       |
| 4K      | 30 fps     | HEVC   | ~140 MB       |
| 720p    | 30 fps     | HEVC   | ~18 MB        |

## ✅ Features

- ✅ Persistent settings across app launches
- ✅ Device capability detection
- ✅ Auto-adjustment for compatibility
- ✅ Real-time file size estimation
- ✅ Slow-motion indicator
- ✅ Recording timer
- ✅ All orientations supported
- ✅ Camera flip (front/back)
- ✅ Reset to defaults option

## 🐛 Known Limitations

- 4K may not be available on older devices
- 240 fps only available at 480p/720p
- Slow-motion requires 120+ fps
- Some frame rates incompatible with 4K

## 🚀 Next Steps

1. Test on physical device (camera features require hardware)
2. Verify settings UI in Profile → Settings
3. Record test videos at different settings
4. Check file sizes match estimates
5. Test slow-motion playback

## 💡 Pro Tips

**For Best Quality:**
- Use 1080p @ 60fps with HEVC
- Enable cinematic stabilization
- Record audio for complete experience

**For Storage Savings:**
- Use 720p @ 30fps with HEVC
- Disable audio if not needed
- Lower frame rate reduces file size

**For Slow-Motion:**
- Select 120 fps minimum
- Use 1080p or lower for best results
- Enable slow-motion toggle
- Records playable at 1/4 speed (120fps → 30fps)

## 🎓 Key Concepts

**Quality** = Resolution (pixels)
- Higher = sharper, larger files

**Format** = Compression codec
- HEVC = smaller, modern
- H.264 = compatible, older

**Frame Rate** = Frames per second
- Higher = smoother, slow-motion capable

**Slow-Motion** = High FPS recording
- Record fast, play slow
- 120 fps → 4x slow-motion
- 240 fps → 8x slow-motion

## 📞 Support

If issues occur:
1. Check device supports selected settings
2. Verify camera permissions granted
3. Try resetting to defaults
4. Lower quality if recording fails
5. Check available storage space

---

**Implementation Complete! ✨**

All video recording options are now available and ready to use. Settings persist automatically and the UI guides users through device limitations.
