#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-LocalBlastStudio}"
DISPLAY_NAME="${DISPLAY_NAME:-Local BLAST Studio}"
BUNDLE_ID="${BUNDLE_ID:-local.blast.studio}"
VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
MIN_MACOS="${MIN_MACOS:-14.0}"
DMG_NAME="${DMG_NAME:-BLAST-Studio-${VERSION}-universal.dmg}"

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Resources/LocalBlastStudioIcon.png"
ICONSET_DIR="$ROOT_DIR/.build/LocalBlastStudio.iconset"
ICNS_PATH="$ROOT_DIR/.build/LocalBlastStudio.icns"
UNIVERSAL_BUILD_DIR="$ROOT_DIR/.build/universal"
STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$DMG_NAME"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

build_arch() {
  local arch="$1"
  local build_path="$UNIVERSAL_BUILD_DIR/$arch"
  local bin_dir
  local binary

  echo "Building $APP_NAME for $arch..." >&2
  swift build -c release --arch "$arch" --product "$APP_NAME" --build-path "$build_path" >&2
  bin_dir="$(swift build -c release --arch "$arch" --product "$APP_NAME" --build-path "$build_path" --show-bin-path 2>/dev/null | tail -n 1)"
  binary="$bin_dir/$APP_NAME"

  if [[ ! -x "$binary" ]]; then
    echo "Expected binary was not created: $binary" >&2
    exit 1
  fi

  printf '%s\n' "$binary"
}

write_info_plist() {
  cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>LocalBlastStudio</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
}

copy_icon() {
  if [[ ! -f "$ICON_SOURCE" ]]; then
    return
  fi

  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
  cp "$ICNS_PATH" "$RESOURCES_DIR/LocalBlastStudio.icns"
}

sign_app() {
  if [[ "${SKIP_CODESIGN:-0}" == "1" ]]; then
    echo "Skipping codesign because SKIP_CODESIGN=1." >&2
    return
  fi

  if ! command -v codesign >/dev/null 2>&1; then
    echo "codesign not found; leaving app unsigned." >&2
    return
  fi

  local identity="${CODESIGN_IDENTITY:--}"
  echo "Signing app with identity: $identity" >&2
  codesign --force --deep --sign "$identity" "$APP_DIR"
}

require_tool swift
require_tool lipo
require_tool sips
require_tool iconutil
require_tool hdiutil
require_tool ditto

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"

ARM_BINARY="$(build_arch arm64)"
INTEL_BINARY="$(build_arch x86_64)"

rm -rf "$APP_DIR" "$STAGING_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Creating universal executable..." >&2
lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
lipo -info "$MACOS_DIR/$APP_NAME"

copy_icon
write_info_plist
sign_app

mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
echo "Creating DMG at $DMG_PATH..." >&2
hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "Created $DMG_PATH"
