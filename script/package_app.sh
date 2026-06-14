#!/usr/bin/env bash
set -euo pipefail

APP_NAME="HostDeck"
BUNDLE_ID="com.hostdeck.app"
MIN_SYSTEM_VERSION="14.0"
VERSION="0.1.0"
BUILD_NUMBER="1"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Sources/HostDeck/Resources/AppIcon/HostDeck.icns"
ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"

cd "$ROOT_DIR"

echo "Building $APP_NAME release binary..."
swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BUILD_DIR/HostDeck_HostDeck.bundle"

rm -rf "$APP_BUNDLE" "$ZIP_PATH"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE"/. "$APP_RESOURCES/"
fi

if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$APP_RESOURCES/HostDeck.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>HostDeck</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 byu_rself. Released under the MIT License.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Embedding non-system dynamic libraries..."
/usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY" 2>/dev/null || true

copy_dylib() {
  local source_path="$1"
  local dest_path="$APP_FRAMEWORKS/$(basename "$source_path")"

  if [[ ! -f "$source_path" ]]; then
    return
  fi

  cp -f "$source_path" "$dest_path"
  chmod u+w "$dest_path"
}

rewrite_to_frameworks() {
  local binary_path="$1"
  local dependency_path="$2"
  local dependency_name
  dependency_name="$(basename "$dependency_path")"

  /usr/bin/install_name_tool -change "$dependency_path" "@rpath/$dependency_name" "$binary_path" 2>/dev/null || true
}

homebrew_dylib_dependencies() {
  local binary_path="$1"

  otool -L "$binary_path" | awk '/\/(opt\/homebrew|usr\/local)\/opt\/.*\/lib\/.*\.dylib/ { print $1 }'
}

LIBSSH2_PATH="$(otool -L "$APP_BINARY" | awk '/libssh2.*\.dylib/ { print $1; exit }')"
if [[ -n "${LIBSSH2_PATH:-}" && "$LIBSSH2_PATH" == /* ]]; then
  copy_dylib "$LIBSSH2_PATH"
  rewrite_to_frameworks "$APP_BINARY" "$LIBSSH2_PATH"

  LIBSSH2_DEST="$APP_FRAMEWORKS/$(basename "$LIBSSH2_PATH")"
  /usr/bin/install_name_tool -id "@rpath/$(basename "$LIBSSH2_PATH")" "$LIBSSH2_DEST" 2>/dev/null || true

  while IFS= read -r dependency_path; do
    copy_dylib "$dependency_path"
    /usr/bin/install_name_tool -change "$dependency_path" "@loader_path/$(basename "$dependency_path")" "$LIBSSH2_DEST" 2>/dev/null || true
  done < <(homebrew_dylib_dependencies "$LIBSSH2_DEST")
fi

for dylib_path in "$APP_FRAMEWORKS"/*.dylib; do
  [[ -e "$dylib_path" ]] || continue
  dylib_name="$(basename "$dylib_path")"
  /usr/bin/install_name_tool -id "@rpath/$dylib_name" "$dylib_path" 2>/dev/null || true

  while IFS= read -r dependency_path; do
    copy_dylib "$dependency_path"
    /usr/bin/install_name_tool -change "$dependency_path" "@loader_path/$(basename "$dependency_path")" "$dylib_path" 2>/dev/null || true
  done < <(homebrew_dylib_dependencies "$dylib_path")
done

echo "Signing app bundle locally..."
if compgen -G "$APP_FRAMEWORKS/*.dylib" >/dev/null; then
  /usr/bin/codesign --force --sign - --timestamp=none "$APP_FRAMEWORKS"/*.dylib
fi
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Creating zip archive..."
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Packaged app: $APP_BUNDLE"
echo "Archive: $ZIP_PATH"
