# Info.plist Privacy Configuration

To make video recording work properly in your PlayerPath app, you need to add the following privacy usage descriptions to your Info.plist file:

## Required Privacy Keys

Add these keys to your `Info.plist` file (you can edit it as Source Code or use the Property List editor in Xcode):

### Camera Usage Description
```xml
<key>NSCameraUsageDescription</key>
<string>PlayerPath needs camera access to record videos of your athletic performance for analysis and improvement.</string>
```

### Microphone Usage Description  
```xml
<key>NSMicrophoneUsageDescription</key>
<string>PlayerPath needs microphone access to record audio along with videos for complete performance analysis.</string>
```

### Photo Library Usage Description (for video uploads)
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>PlayerPath needs photo library access to allow you to upload existing videos for analysis.</string>
```

## Complete Info.plist Example

Here's how your privacy section should look in Info.plist:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Your other app configuration keys... -->
    
    <!-- Privacy - Camera Usage Description -->
    <key>NSCameraUsageDescription</key>
    <string>PlayerPath needs camera access to record videos of your athletic performance for analysis and improvement.</string>
    
    <!-- Privacy - Microphone Usage Description -->
    <key>NSMicrophoneUsageDescription</key>
    <string>PlayerPath needs microphone access to record audio along with videos for complete performance analysis.</string>
    
    <!-- Privacy - Photo Library Usage Description -->
    <key>NSPhotoLibraryUsageDescription</key>
    <string>PlayerPath needs photo library access to allow you to upload existing videos for analysis.</string>
    
    <!-- Your other app configuration keys... -->
</dict>
</plist>
```

## How to Add These in Xcode

1. **Open your project in Xcode**
2. **Select your target** (PlayerPath)
3. **Go to the Info tab**
4. **Click the + button** to add new entries
5. **Add each privacy key** and provide the usage description

OR

1. **Right-click on Info.plist** in your project navigator
2. **Choose "Open As" > "Source Code"**
3. **Add the XML entries** shown above
4. **Save the file**

## Important Notes

- **These descriptions are required** - Without them, iOS will crash your app when it tries to access camera/microphone
- **Be descriptive** - Users will see these messages when prompted for permissions
- **Test on device** - Camera permissions only work on physical devices, not simulators
- **Handle permission denial gracefully** - The updated VideoRecorderView code now handles this properly

After adding these to your Info.plist, your video recording should work properly!