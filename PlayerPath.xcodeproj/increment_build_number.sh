#!/bin/bash

# Auto-increment build number script for PlayerPath
# This script should be added as a Run Script build phase in Xcode

# Only run during archive builds or when explicitly building for release
if [ "$CONFIGURATION" != "Release" ] && [ "$ACTION" != "archive" ]; then
    echo "Skipping build number increment - not a release build or archive"
    exit 0
fi

# Get the path to the Info.plist file
INFO_PLIST_PATH="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
PROJECT_INFO_PLIST_PATH="${PROJECT_DIR}/${PRODUCT_NAME}/Info.plist"

# Check if we're building and have access to the project plist
if [ ! -f "$PROJECT_INFO_PLIST_PATH" ]; then
    echo "Warning: Could not find Info.plist at $PROJECT_INFO_PLIST_PATH"
    # Try alternate common locations
    PROJECT_INFO_PLIST_PATH="${PROJECT_DIR}/Info.plist"
    if [ ! -f "$PROJECT_INFO_PLIST_PATH" ]; then
        PROJECT_INFO_PLIST_PATH="${SRCROOT}/Info.plist"
        if [ ! -f "$PROJECT_INFO_PLIST_PATH" ]; then
            echo "Error: Could not locate Info.plist file"
            exit 1
        fi
    fi
fi

echo "Using Info.plist at: $PROJECT_INFO_PLIST_PATH"

# Get current build number
CURRENT_BUILD_NUMBER=$(defaults read "$PROJECT_INFO_PLIST_PATH" CFBundleVersion 2>/dev/null)

if [ -z "$CURRENT_BUILD_NUMBER" ]; then
    echo "Warning: CFBundleVersion not found, starting from 1"
    CURRENT_BUILD_NUMBER="1"
fi

# Increment build number
NEW_BUILD_NUMBER=$((CURRENT_BUILD_NUMBER + 1))

echo "Incrementing build number from $CURRENT_BUILD_NUMBER to $NEW_BUILD_NUMBER"

# Update the Info.plist file
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD_NUMBER" "$PROJECT_INFO_PLIST_PATH"

if [ $? -eq 0 ]; then
    echo "✅ Successfully updated build number to $NEW_BUILD_NUMBER"
else
    echo "❌ Failed to update build number"
    exit 1
fi

# Optional: Also update the built product's Info.plist if it exists
if [ -f "$INFO_PLIST_PATH" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD_NUMBER" "$INFO_PLIST_PATH" 2>/dev/null
    echo "Updated built product Info.plist as well"
fi

echo "Build number increment complete"