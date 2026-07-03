#!/bin/bash

# Exit immediately if any command fails.
set -euo pipefail

APP_NAME="Fan Control"
APP_EXECUTABLE="FanControl"
HELPER_EXECUTABLE="smc-helper"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

BUILD_DIR="${BUILD_DIR:-.build}"
PRODUCTS_DIR="$BUILD_DIR/products"
MODULE_CACHE_DIR="${MODULE_CACHE_DIR:-$BUILD_DIR/module-cache}"

MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"
ARCHS="${ARCHS:-arm64 x86_64}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

HELPER_IDENTIFIER="com.pair.FanControl.helper"

HELPER_SOURCES=(
    Core/SMC.swift
    Shared/FanControlHelperProtocol.swift
    Helper/main.swift
)

APP_SOURCES=(
    Core/SMC.swift
    Core/SystemStatusReader.swift
    Shared/FanControlHelperProtocol.swift
    Models/*.swift
    ViewModels/*.swift
    Views/*.swift
    App/FanControlApp.swift
)

export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

create_universal_binary() {
    local output="$1"
    shift

    if [ "$#" -eq 1 ]; then
        cp "$1" "$output"
    else
        lipo -create "$@" -output "$output"
    fi

    chmod +x "$output"
}

echo "=== Building Fan Control App Bundle ==="
echo "Deployment target: macOS $MACOS_DEPLOYMENT_TARGET"
echo "Architectures: $ARCHS"

rm -rf "$APP_DIR" "$PRODUCTS_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$PRODUCTS_DIR" "$MODULE_CACHE_DIR"

app_slices=()
helper_slices=()

for arch in $ARCHS; do
    target="${arch}-apple-macosx${MACOS_DEPLOYMENT_TARGET}"
    arch_dir="$PRODUCTS_DIR/$arch"
    helper_output="$arch_dir/$HELPER_EXECUTABLE"
    app_output="$arch_dir/$APP_EXECUTABLE"

    mkdir -p "$arch_dir"

    echo "Compiling $HELPER_EXECUTABLE for $arch..."
    swiftc \
        -target "$target" \
        -sdk "$SDK_PATH" \
        -o "$helper_output" \
        -framework Security \
        "${HELPER_SOURCES[@]}"

    echo "Compiling $APP_EXECUTABLE for $arch..."
    swiftc \
        -parse-as-library \
        -target "$target" \
        -sdk "$SDK_PATH" \
        -o "$app_output" \
        -framework Cocoa \
        -framework SwiftUI \
        -framework IOKit \
        -framework UserNotifications \
        -framework ServiceManagement \
        "${APP_SOURCES[@]}"

    helper_slices+=("$helper_output")
    app_slices+=("$app_output")
done

echo "Creating app bundle binaries..."
create_universal_binary "$MACOS_DIR/$HELPER_EXECUTABLE" "${helper_slices[@]}"
create_universal_binary "$MACOS_DIR/$APP_EXECUTABLE" "${app_slices[@]}"

echo "Writing Info.plist..."
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>com.pair.FanControl</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MACOS_DEPLOYMENT_TARGET</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
</dict>
</plist>
EOF

echo "Writing privileged helper launchd plist..."
LAUNCH_DAEMONS_DIR="$CONTENTS_DIR/Library/LaunchDaemons"
mkdir -p "$LAUNCH_DAEMONS_DIR"
cat <<EOF > "$LAUNCH_DAEMONS_DIR/$HELPER_IDENTIFIER.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$HELPER_IDENTIFIER</string>
    <key>BundleProgram</key>
    <string>Contents/MacOS/$HELPER_EXECUTABLE</string>
    <key>MachServices</key>
    <dict>
        <key>$HELPER_IDENTIFIER</key>
        <true/>
    </dict>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>com.pair.FanControl</string>
    </array>
</dict>
</plist>
EOF

if [ -f "app_icon.png" ]; then
    echo "Creating AppIcon.icns..."
    iconset_dir="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$iconset_dir"
    mkdir -p "$iconset_dir"

    sips -s format png -z 16 16 app_icon.png --out "$iconset_dir/icon_16x16.png" >/dev/null
    sips -s format png -z 32 32 app_icon.png --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
    sips -s format png -z 32 32 app_icon.png --out "$iconset_dir/icon_32x32.png" >/dev/null
    sips -s format png -z 64 64 app_icon.png --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
    sips -s format png -z 128 128 app_icon.png --out "$iconset_dir/icon_128x128.png" >/dev/null
    sips -s format png -z 256 256 app_icon.png --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
    sips -s format png -z 256 256 app_icon.png --out "$iconset_dir/icon_256x256.png" >/dev/null
    sips -s format png -z 512 512 app_icon.png --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
    sips -s format png -z 512 512 app_icon.png --out "$iconset_dir/icon_512x512.png" >/dev/null
    sips -s format png -z 1024 1024 app_icon.png --out "$iconset_dir/icon_512x512@2x.png" >/dev/null

    if ! iconutil -c icns "$iconset_dir" -o "$RESOURCES_DIR/AppIcon.icns"; then
        echo "Warning: unable to create AppIcon.icns. App bundle will use the default generic icon."
        rm -f "$RESOURCES_DIR/AppIcon.icns"
    fi
else
    echo "Warning: app_icon.png not found. App bundle will have default generic icon."
fi

echo "$APP_EXECUTABLE architectures: $(lipo -archs "$MACOS_DIR/$APP_EXECUTABLE")"
echo "$HELPER_EXECUTABLE architectures: $(lipo -archs "$MACOS_DIR/$HELPER_EXECUTABLE")"
echo "$APP_EXECUTABLE deployment targets:"
vtool -show-build "$MACOS_DIR/$APP_EXECUTABLE" | grep "minos"
echo "$HELPER_EXECUTABLE deployment targets:"
vtool -show-build "$MACOS_DIR/$HELPER_EXECUTABLE" | grep "minos"

# 7. Codesign app bundle and binaries
# The helper is signed first (inner-to-outer) with an explicit identifier so the
# app's XPC code-signing requirement can pin it. The app bundle is signed last,
# which seals the LaunchDaemons plist. A real Developer ID identity is required
# for SMAppService to register the daemon and for the mutual code-sign checks to
# pass; ad-hoc ("-") builds compile and run but the daemon won't register.
echo "Codesigning app and binaries..."
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --identifier "$HELPER_IDENTIFIER" "$MACOS_DIR/$HELPER_EXECUTABLE"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$MACOS_DIR/$APP_EXECUTABLE"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$APP_DIR"

# 8. Create DMG disk image
echo "Packaging to DMG..."
rm -f "Fan Control.dmg"
mkdir -p dist
cp -R "$APP_DIR" dist/
# Add a symbolic link to /Applications for easy drag-and-drop installation
ln -s /Applications dist/Applications
hdiutil create -volname "Fan Control v2.0" -srcfolder dist -ov -format UDZO "Fan Control.dmg"
rm -rf dist

echo "Codesigning DMG..."
codesign --force --sign "$SIGNING_IDENTITY" "Fan Control.dmg"

echo "=== Build and Packaging Complete: 'Fan Control.dmg' created successfully ==="
