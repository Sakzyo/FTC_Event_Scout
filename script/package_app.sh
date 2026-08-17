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

build_swift_app() {
  swift build "$@" "${SWIFT_ARGS[@]}" >"$SWIFT_LOG" 2>&1
}

report_swift_failure() {
  rm -rf "$APP_BUNDLE"

  if grep -Eq \
    'SDK is not supported by the compiler|unable to find utility "xcodebuild"|invalid active developer path|tool .xcodebuild. requires Xcode|failed to get the SDK path' \
    "$SWIFT_LOG"; then
    echo "The selected Apple toolchain cannot compile this macOS app." >&2
    echo "Install a current Xcode release, select it with xcode-select, and run this script again." >&2
  else
    echo "The native SwiftUI app did not compile." >&2
    grep -m 1 -E '(^|: )error:' "$SWIFT_LOG" >&2 || true
  fi

  echo "Build details: $SWIFT_LOG" >&2
  exit 1
}

if ! build_swift_app; then
  if grep -q 'sandbox-exec: sandbox_apply: Operation not permitted' "$SWIFT_LOG"; then
    # Codex and some CI runners already execute inside a sandbox. SwiftPM's
    # nested manifest sandbox cannot start there, so retry without nesting it.
    build_swift_app --disable-sandbox || report_swift_failure
  else
    report_swift_failure
  fi
fi

BIN_PATH="$(swift build --show-bin-path --cache-path "$BUILD_ROOT/swiftpm-cache")"
if [[ "$CONFIGURATION" == "release" ]]; then
  BIN_PATH="$(swift build --show-bin-path --cache-path "$BUILD_ROOT/swiftpm-cache" -c release)"
fi
BUILD_BINARY="$BIN_PATH/$EXECUTABLE_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$BACKEND_RESOURCES"
cp "$BUILD_BINARY" "$APP_MACOS/$EXECUTABLE_NAME"
chmod +x "$APP_MACOS/$EXECUTABLE_NAME"

for file in \
  web_server.py scrape.py calculate_opr_from_csv.py \
  historical_opr.py opr_calc.py; do
  cp "$ROOT_DIR/$file" "$BACKEND_RESOURCES/$file"
done
cp -R "$ROOT_DIR/event_results" "$BACKEND_RESOURCES/event_results"
cp -R "$ROOT_DIR/events_teams_opr" "$BACKEND_RESOURCES/events_teams_opr"
cp -R "$ROOT_DIR/Sources/FTCEventScout/Resources/en.lproj" "$APP_RESOURCES/en.lproj"

while IFS= read -r resource_bundle; do
  cp -R "$resource_bundle" "$APP_RESOURCES/"
  while IFS= read -r localization_directory; do
    localization_name="$(basename "$localization_directory")"
    mkdir -p "$APP_RESOURCES/$localization_name"
    cp -R "$localization_directory/." "$APP_RESOURCES/$localization_name/"
  done < <(find "$resource_bundle" -maxdepth 1 -type d -name '*.lproj' -print)
done < <(find "$BIN_PATH" -maxdepth 1 -type d -name '*.bundle' -print)

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

codesign --force --sign - "$APP_BUNDLE" >/dev/null
echo "Packaged $APP_BUNDLE (native SwiftUI, $CONFIGURATION)"
