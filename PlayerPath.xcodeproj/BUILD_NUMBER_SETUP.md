# Auto-Increment Build Number Setup Guide

This guide explains how to set up automatic build number incrementing for your PlayerPath app.

## What This Does

The script automatically increments your app's build number (CFBundleVersion) every time you:
- Create an archive for distribution
- Build in Release configuration

This ensures each build has a unique build number, which is required for App Store submissions.

## Setup Instructions

### Step 1: Add the Script to Xcode

1. **Open your PlayerPath.xcodeproj in Xcode**

2. **Select your project** in the Project Navigator (top item)

3. **Select your target** (PlayerPath)

4. **Go to Build Phases tab**

5. **Click the + button** and choose "New Run Script Phase"

6. **Drag the new Run Script phase** to be **BEFORE** "Compile Sources" (important!)

7. **Name the script phase**: "Auto-increment Build Number"

8. **In the script text area**, paste the following:

```bash
# Only run during Release builds or archives
if [ "$CONFIGURATION" != "Release" ] && [ "$ACTION" != "archive" ]; then
    echo "Skipping build number increment - not a release build or archive"
    exit 0
fi

# Get current build number from Info.plist
INFO_PLIST_PATH="${PROJECT_DIR}/${PRODUCT_NAME}/Info.plist"

# Check alternate locations if not found
if [ ! -f "$INFO_PLIST_PATH" ]; then
    INFO_PLIST_PATH="${PROJECT_DIR}/Info.plist"
fi

if [ ! -f "$INFO_PLIST_PATH" ]; then
    INFO_PLIST_PATH="${SRCROOT}/Info.plist"
fi

if [ ! -f "$INFO_PLIST_PATH" ]; then
    echo "Error: Could not locate Info.plist file"
    exit 1
fi

echo "Using Info.plist at: $INFO_PLIST_PATH"

# Get current build number
CURRENT_BUILD_NUMBER=$(defaults read "$INFO_PLIST_PATH" CFBundleVersion 2>/dev/null || echo "1")

# Increment build number  
NEW_BUILD_NUMBER=$((CURRENT_BUILD_NUMBER + 1))

echo "Incrementing build number from $CURRENT_BUILD_NUMBER to $NEW_BUILD_NUMBER"

# Update the Info.plist file
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD_NUMBER" "$INFO_PLIST_PATH"

if [ $? -eq 0 ]; then
    echo "✅ Successfully updated build number to $NEW_BUILD_NUMBER"
else
    echo "❌ Failed to update build number"
    exit 1
fi
```

### Step 2: Configure Input Files (Optional but Recommended)

1. **In the Run Script phase**, expand "Input Files"
2. **Add**: `$(PROJECT_DIR)/$(PRODUCT_NAME)/Info.plist`
3. **Or add**: `$(PROJECT_DIR)/Info.plist` (if that's where your Info.plist is located)

### Step 3: Configure Output Files (Optional but Recommended)

1. **In the Run Script phase**, expand "Output Files"  
2. **Add**: `$(PROJECT_DIR)/$(PRODUCT_NAME)/Info.plist`

This helps Xcode's build system understand file dependencies.

### Step 4: Set Initial Build Number

Make sure your Info.plist has a CFBundleVersion entry:

1. **Open Info.plist** (right-click → Open As → Source Code)
2. **Add this if missing**:
```xml
<key>CFBundleVersion</key>
<string>1</string>
```

Or use the Property List editor in Xcode:
1. **Open Info.plist** in Xcode
2. **Add row**: Bundle version (CFBundleVersion) 
3. **Set value**: 1

## How It Works

- **Debug builds**: Build number stays the same
- **Release builds**: Build number increments
- **Archive builds**: Build number increments (regardless of configuration)

## Testing

1. **Build for Debug**: Build number should NOT change
2. **Build for Release**: Build number should increment
3. **Archive**: Build number should increment

## Troubleshooting

### Script doesn't run
- Make sure the Run Script phase is enabled (checkbox checked)
- Ensure it's placed BEFORE "Compile Sources" in Build Phases

### Can't find Info.plist
- Check the path in the script matches your Info.plist location
- Common locations: `$(PROJECT_DIR)/Info.plist` or `$(PROJECT_DIR)/$(PRODUCT_NAME)/Info.plist`

### Permission errors
- The script should have the correct permissions automatically
- If issues persist, you can make the external script executable: `chmod +x increment_build_number.sh`

### Build number not incrementing
- Check the build log in Xcode for script output
- Ensure you're building in Release configuration or creating an archive
- Verify CFBundleVersion exists in your Info.plist

## Alternative: Using agvtool

If you prefer to use Apple's agvtool, replace the script with:

```bash
if [ "$CONFIGURATION" = "Release" ] || [ "$ACTION" = "archive" ]; then
    agvtool bump -all
fi
```

But you'll need to set "Current Project Version" in your project settings first.

## Benefits

- ✅ Automatic build number management
- ✅ Only runs for release/archive builds  
- ✅ Prevents duplicate build numbers
- ✅ Required for App Store Connect uploads
- ✅ No manual intervention needed