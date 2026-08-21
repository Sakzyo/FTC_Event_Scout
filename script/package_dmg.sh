#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="FTC Event Scout"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
STAGING_DIR="$BUILD_ROOT/dmg-root"

"$ROOT_DIR/script/package_app.sh" release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
DMG_NAME="FTC-Event-Scout-$VERSION.dmg"
DMG_PATH="${FTC_SCOUT_DMG_PATH:-$DIST_DIR/$DMG_NAME}"
DMG_DIRECTORY="$(dirname "$DMG_PATH")"
DMG_FILENAME="$(basename "$DMG_PATH")"
CHECKSUM_FILENAME="$DMG_FILENAME.sha256"
CHECKSUM_PATH="$DMG_DIRECTORY/$CHECKSUM_FILENAME"
VOLUME_NAME="$APP_NAME $VERSION"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
/usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$DMG_DIRECTORY"
rm -f "$DMG_PATH" "$CHECKSUM_PATH"
/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

/usr/bin/hdiutil verify "$DMG_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
(
  cd "$DMG_DIRECTORY"
  /usr/bin/shasum -a 256 "$DMG_FILENAME" >"$CHECKSUM_FILENAME"
)

echo "Packaged $DMG_PATH"
echo "Checksum $CHECKSUM_PATH"
