#!/bin/bash
# Build and install Hype.app to /Applications
set -e

echo "Building release..."
swift build -c release

APP="/Applications/Hype.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

echo "Installing binary..."
cp .build/release/Hype "$APP/Contents/MacOS/Hype"

echo "Installing icons..."
cp Sources/Hype/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Sources/Hype/Resources/HypeDocIcon.icns "$APP/Contents/Resources/HypeDocIcon.icns"

echo "Installing Info.plist..."
cp build/Hype.app/Contents/Info.plist "$APP/Contents/Info.plist"

echo "Re-signing..."
codesign --force --sign - --deep "$APP"

echo "Done! Hype.app installed to /Applications"
