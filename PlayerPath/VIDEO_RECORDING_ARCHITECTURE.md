# Video Recording Options - Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE LAYER                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌───────────────────┐         ┌──────────────────────────────┐    │
│  │   Profile View    │────────>│ VideoRecordingSettingsView   │    │
│  │   (More Tab)      │         │                              │    │
│  │                   │         │  - Quality Picker            │    │
│  │  Settings:        │         │  - Format Toggle             │    │
│  │  • General        │         │  - Frame Rate Selector       │    │
│  │  • Video Recording│         │  - Slow-Mo Toggle            │    │
│  │  • Security       │         │  - Stabilization Picker      │    │
│  │  • Notifications  │         │  - File Size Preview         │    │
│  └───────────────────┘         │  - Reset Button              │    │
│                                 └──────────┬───────────────────┘    │
│                                            │                         │
│                                            │ reads/writes            │
└────────────────────────────────────────────┼─────────────────────────┘
                                             │
                                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        SETTINGS MODEL LAYER                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │           VideoRecordingSettings (@Observable)                │  │
│  │                                                                │  │
│  │  Properties:                      Methods:                    │  │
│  │  • quality: VideoQuality          • isQualitySupported()      │  │
│  │  • format: VideoFormat            • isFrameRateSupported()    │  │
│  │  • frameRate: FrameRate           • compatibleFrameRates()    │  │
│  │  • slowMotionEnabled: Bool        • resetToDefaults()         │  │
│  │  • audioEnabled: Bool             • saveSettings()            │  │
│  │  • stabilizationMode: Mode        • estimatedFileSize         │  │
│  │                                                                │  │
│  │  Computed:                        Persistence:                │  │
│  │  • estimatedFileSizePerMinute     • UserDefaults (auto-save) │  │
│  │  • supportsSlowMotion             • Loads on init            │  │
│  │  • settingsDescription                                        │  │
│  └────────────────────────┬─────────────────────────────────────┘  │
│                           │                                          │
└───────────────────────────┼──────────────────────────────────────────┘
                            │
                            │ provides settings to
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         CAMERA LAYER                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              AdvancedCameraViewController                    │   │
│  │              (UIKit/AVFoundation)                            │   │
│  │                                                               │   │
│  │  Setup:                          UI Elements:                │   │
│  │  • AVCaptureSession              • Record Button (80x80)     │   │
│  │  • AVCaptureDevice               • Recording Timer           │   │
│  │  • AVCaptureDeviceInput          • Settings Label            │   │
│  │  • AVCaptureMovieFileOutput      • Slow-Mo Indicator         │   │
│  │  • AVCaptureVideoPreviewLayer    • Flip Camera Button        │   │
│  │                                   • Cancel Button             │   │
│  │  Configuration:                                               │   │
│  │  • Quality → Session Preset                                  │   │
│  │  • Frame Rate → Device Config                                │   │
│  │  • Format → Codec Selection                                  │   │
│  │  • Stabilization → Connection                                │   │
│  └────────────────────┬─────────────────────────────────────────┘  │
│                       │                                              │
└───────────────────────┼──────────────────────────────────────────────┘
                        │
                        │ outputs
                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         OUTPUT LAYER                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                     Recorded Video File                      │   │
│  │                                                               │   │
│  │  Properties:                                                 │   │
│  │  • URL: FileManager.temporaryDirectory                       │   │
│  │  • Format: .mov or .mp4                                      │   │
│  │  • Codec: HEVC or H.264                                      │   │
│  │  • Resolution: 480p - 4K                                     │   │
│  │  • Frame Rate: 24 - 240 fps                                  │   │
│  │  • Size: Estimated by settings                               │   │
│  │                                                               │   │
│  │  Metadata:                                                   │   │
│  │  • Duration                                                  │   │
│  │  • Orientation                                               │   │
│  │  • Creation Date                                             │   │
│  │  • Device Info                                               │   │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘


DATA FLOW DIAGRAM
==================

User Action                     Settings                    Camera
─────────────────────────────────────────────────────────────────────

1. User opens                                                
   Profile/Settings ───────────────────────┐                
                                            │                
2. Taps                                     │                
   "Video Recording" ──────────────────────┤                
                                            ▼                
3. Selects quality,            ┌─────────────────────────┐  
   format, frame rate ────────>│ VideoRecordingSettings  │  
                                │     (Observable)        │  
4. Settings auto-save           │  • Validates            │  
   to UserDefaults <────────────│  • Persists             │  
                                │  • Computes estimates   │  
5. User taps "Done"             └────────┬────────────────┘  
   Settings persist                      │                   
                                          │                   
6. User opens                             │                   
   video recorder ───────────────────────┤                   
                                          │                   
7. Camera reads settings  <───────────────┘                   
   from shared instance                                       
                                                              
8. Camera configures            ┌───────────────────────┐    
   AVFoundation ───────────────>│  AVCaptureSession     │    
                                │  • Quality preset     │    
9. User taps record             │  • Frame rate config  │    
                                │  • Codec selection    │    
10. Video records with          │  • Stabilization      │    
    selected settings           └──────────┬────────────┘    
                                           │                  
11. Recording completes                    │                  
                                           ▼                  
12. Video file created          ┌───────────────────────┐    
    with properties ───────────>│    Video File (.mov)  │    
                                │  • Quality applied    │    
13. File passed to app          │  • Format encoded     │    
    for processing <────────────│  • Metadata included  │    
                                └───────────────────────┘    


SETTINGS VALIDATION FLOW
==========================

User Selection              Validation                  Result
──────────────────────────────────────────────────────────────

Select 4K Quality    ───>  Device Check      ───>  ✅ Supported / ❌ Grayed Out
                                                    
Select 240 fps       ───>  Quality Check     ───>  ✅ if 480p/720p
                                                    ❌ if 1080p/4K
                                                    
Enable Slow-Motion   ───>  Frame Rate Check  ───>  ✅ if ≥ 120 fps
                                                    ❌ if < 120 fps
                                                    
Change Quality       ───>  Frame Rate Valid? ───>  Auto-adjust frame rate
  to 4K                                             if incompatible
                                                    
Select Frame Rate    ───>  Slow-Mo Valid?    ───>  Disable slow-mo toggle
  < 120 fps                                         if enabled


FILE SIZE CALCULATION
======================

Input: Settings
───────────────

quality.estimatedMBPerMinute = baseSize
format multiplier = (HEVC ? 0.7 : 1.0)
frameRate.multiplier = fps / 30.0

Calculation:
────────────

estimatedSize = baseSize × formatMultiplier × frameRateMultiplier

Examples:
─────────

1080p @ 30fps HEVC:
  60 × 0.7 × 1.0 = 42 MB/min

1080p @ 60fps H.264:
  60 × 1.0 × 2.0 = 120 MB/min

4K @ 30fps HEVC:
  200 × 0.7 × 1.0 = 140 MB/min

720p @ 120fps HEVC:
  25 × 0.7 × 4.0 = 70 MB/min


INTEGRATION POINTS
==================

┌─────────────────────┐
│  Existing App Code  │
└─────────────────────┘
          │
          ├──> ProfileView.swift
          │    • Add "Video Recording" link ✅
          │
          ├──> VideoRecorderView_Refactored.swift
          │    • Replace NativeCameraView with AdvancedCameraView
          │    • OR offer both as options
          │
          ├──> PlayResultOverlayView.swift
          │    • No changes needed
          │    • Works with any video URL
          │
          └──> VideoClipsView.swift
               • No changes needed
               • Displays videos regardless of settings


KEY DESIGN PATTERNS
===================

1. Observable Pattern
   • @Observable macro for reactive UI
   • Automatic SwiftUI updates

2. Singleton Pattern
   • VideoRecordingSettings.shared
   • Global access to settings

3. Strategy Pattern
   • Quality/Format/FrameRate enums
   • Encapsulated behavior

4. Facade Pattern
   • AdvancedCameraView wraps AVFoundation
   • Simple interface, complex implementation

5. Builder Pattern
   • Settings built through UI selections
   • Validated and applied incrementally
```
