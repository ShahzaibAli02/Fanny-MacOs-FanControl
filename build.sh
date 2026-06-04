#!/bin/bash

# Exit immediately if any command fails
set -e

echo "=== Building Fan Control App Bundle ==="

# 1. Create directory structure
APP_DIR="Fan Control.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 2. Compile Helper CLI
echo "Compiling smc-helper..."
swiftc -o smc-helper Core/SMC.swift Helper/main.swift

# 3. Compile SwiftUI App
echo "Compiling FanControl..."
swiftc -parse-as-library -o FanControl -sdk $(xcrun --show-sdk-path) -framework Cocoa -framework SwiftUI -framework IOKit Core/SMC.swift Models/*.swift ViewModels/*.swift Views/*.swift App/FanControlApp.swift

# 4. Move binaries to app bundle
mv -f smc-helper "$MACOS_DIR/smc-helper"
mv -f FanControl "$MACOS_DIR/FanControl"

# 5. Write Info.plist
echo "Writing Info.plist..."
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FanControl</string>
    <key>CFBundleIdentifier</key>
    <string>com.pair.FanControl</string>
    <key>CFBundleName</key>
    <string>Fan Control</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
</dict>
</plist>
EOF

# 6. Generate app icon from app_icon.png
if [ -f "app_icon.png" ]; then
    echo "Creating AppIcon.icns..."
    mkdir -p app.iconset
    sips -s format png -z 16 16     app_icon.png --out app.iconset/icon_16x16.png
    sips -s format png -z 32 32     app_icon.png --out app.iconset/icon_16x16@2x.png
    sips -s format png -z 32 32     app_icon.png --out app.iconset/icon_32x32.png
    sips -s format png -z 64 64     app_icon.png --out app.iconset/icon_32x32@2x.png
    sips -s format png -z 128 128   app_icon.png --out app.iconset/icon_128x128.png
    sips -s format png -z 256 256   app_icon.png --out app.iconset/icon_128x128@2x.png
    sips -s format png -z 256 256   app_icon.png --out app.iconset/icon_256x256.png
    sips -s format png -z 512 512   app_icon.png --out app.iconset/icon_256x256@2x.png
    sips -s format png -z 512 512   app_icon.png --out app.iconset/icon_512x512.png
    sips -s format png -z 1024 1024 app_icon.png --out app.iconset/icon_512x512@2x.png
    
    iconutil -c icns app.iconset --o "$RESOURCES_DIR/AppIcon.icns"
    rm -rf app.iconset
else
    echo "Warning: app_icon.png not found. App bundle will have default generic icon."
fi

echo "=== Build Complete: '$APP_DIR' created successfully ==="
