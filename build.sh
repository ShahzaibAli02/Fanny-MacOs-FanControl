#!/bin/bash

# Exit immediately if any command fails.
set -euo pipefail

APP_NAME="Fan Control"
APP_EXECUTABLE="FanControl"
HELPER_EXECUTABLE="smc-helper"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Shahzaib Ali (VJ3BBPZBDU)}"

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

HELPER_SOURCES=(
    Core/SMC.swift
    Helper/main.swift
)

APP_SOURCES=(
    Core/SMC.swift
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
    <string>AppIcon</string>
</dict>
</plist>
EOF

if [ -f "app_icon.png" ]; then
    echo "Copying application icon..."
    sips -s format png app_icon.png --out "$RESOURCES_DIR/AppIcon.png" >/dev/null
else
    echo "Warning: app_icon.png not found. App bundle will use the default generic icon."
fi

echo "$APP_EXECUTABLE architectures: $(lipo -archs "$MACOS_DIR/$APP_EXECUTABLE")"
echo "$HELPER_EXECUTABLE architectures: $(lipo -archs "$MACOS_DIR/$HELPER_EXECUTABLE")"
echo "$APP_EXECUTABLE deployment targets:"
vtool -show-build "$MACOS_DIR/$APP_EXECUTABLE" | grep "minos"
echo "$HELPER_EXECUTABLE deployment targets:"
vtool -show-build "$MACOS_DIR/$HELPER_EXECUTABLE" | grep "minos"

# 7. Codesign app bundle and binaries
echo "Codesigning app and binaries..."
codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$MACOS_DIR/$HELPER_EXECUTABLE"
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
