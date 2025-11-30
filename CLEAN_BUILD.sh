#!/bin/bash
# Nuclear clean build script

echo "🧹 Killing Xcode and simulators..."
killall Xcode 2>/dev/null
killall Simulator 2>/dev/null

echo "🗑️ Deleting DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/*

echo "🗑️ Deleting build folder..."
cd "/Users/Trey/Desktop/PlayerPath" || exit
rm -rf build/

echo "🗑️ Cleaning Swift package cache..."
rm -rf .build/
rm -rf ~/Library/Caches/org.swift.swiftpm/

echo "✅ Done! Now:"
echo "   1. Open Xcode"
echo "   2. Product > Clean Build Folder (Shift+Cmd+K)"
echo "   3. Build and Run"
echo ""
echo "The new logging will show:"
echo "   ============================================================"
echo "   🔄 GamesDashboardViewModel.refresh() CALLED"
echo "   ============================================================"
