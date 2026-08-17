#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-debug}"
if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "usage: $0 [debug|release]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="FTC Event Scout"
EXECUTABLE_NAME="FTCEventScout"
BUNDLE_ID="org.ftceventscout.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
BACKEND_RESOURCES="$APP_RESOURCES/Backend"
SWIFT_LOG="$BUILD_ROOT/swift-build.log"

mkdir -p "$BUILD_ROOT/ModuleCache" "$BUILD_ROOT/clang-module-cache" "$BUILD_ROOT/swiftpm-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-module-cache"

SWIFT_ARGS=(--cache-path "$BUILD_ROOT/swiftpm-cache" --product "$EXECUTABLE_NAME")
if [[ "$CONFIGURATION" == "release" ]]; then
  SWIFT_ARGS+=(-c release)
fi

if swift build "${SWIFT_ARGS[@]}" >"$SWIFT_LOG" 2>&1; then
  BIN_PATH="$(swift build --show-bin-path --cache-path "$BUILD_ROOT/swiftpm-cache")"
  if [[ "$CONFIGURATION" == "release" ]]; then
    BIN_PATH="$(swift build --show-bin-path --cache-path "$BUILD_ROOT/swiftpm-cache" -c release)"
  fi
  BUILD_BINARY="$BIN_PATH/$EXECUTABLE_NAME"
  BUILD_IMPLEMENTATION="SwiftUI"
else
  echo "SwiftPM could not use the installed Command Line Tools; building the equivalent AppKit shell."
  echo "SwiftPM details: $SWIFT_LOG"
  FALLBACK_DIR="$BUILD_ROOT/appkit-$CONFIGURATION"
  mkdir -p "$FALLBACK_DIR" "$BUILD_ROOT/clang-module-cache-objc"
  CLANG_OPT=(-O0 -g)
  if [[ "$CONFIGURATION" == "release" ]]; then
    CLANG_OPT=(-O2)
  fi
  clang -fobjc-arc -fmodules \
    -fmodules-cache-path="$BUILD_ROOT/clang-module-cache-objc" \
    -mmacosx-version-min=14.0 "${CLANG_OPT[@]}" \
    "$ROOT_DIR/Sources/AppKitFallback/main.m" \
    "$ROOT_DIR/Sources/AppKitFallback/FTCSettingsWindowController.m" \
    -o "$FALLBACK_DIR/$EXECUTABLE_NAME" \
    -framework Cocoa -framework WebKit -framework Security
  BUILD_BINARY="$FALLBACK_DIR/$EXECUTABLE_NAME"
  BUILD_IMPLEMENTATION="AppKit compatibility shell"
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$BACKEND_RESOURCES"
cp "$BUILD_BINARY" "$APP_MACOS/$EXECUTABLE_NAME"
chmod +x "$APP_MACOS/$EXECUTABLE_NAME"

for file in \
  index.html styles.css favicon.svg web_server.py scrape.py \
  calculate_opr_from_csv.py historical_opr.py opr_calc.py event.py; do
  cp "$ROOT_DIR/$file" "$BACKEND_RESOURCES/$file"
done
cp -R "$ROOT_DIR/event_results" "$BACKEND_RESOURCES/event_results"
cp -R "$ROOT_DIR/events_teams_opr" "$BACKEND_RESOURCES/events_teams_opr"

ICONSET="$BUILD_ROOT/FTCEventScout.iconset"
rm -rf "$ICONSET"
python3 "$ROOT_DIR/script/generate_app_icon.py" "$ICONSET" "$APP_RESOURCES/AppIcon.icns"

cat >"$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
  </dict>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
echo "Packaged $APP_BUNDLE ($BUILD_IMPLEMENTATION, $CONFIGURATION)"
