#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -gt 1 ]]; then
  echo "usage: $0 [finalized-app-path]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build"
APP_BUNDLE="${1:-${FTC_SCOUT_UPDATE_APP_PATH:-$ROOT_DIR/dist/FTC Event Scout.app}}"
UPDATE_DIR="${FTC_SCOUT_UPDATE_DIR:-$ROOT_DIR/dist/updates}"
SPARKLE_TOOLS="$BUILD_ROOT/artifacts/sparkle/Sparkle/bin"
KEY_ACCOUNT="${FTC_SCOUT_SPARKLE_KEY_ACCOUNT:-org.ftceventscout.app}"

if [[ ! -d "$APP_BUNDLE" || ! -f "$APP_BUNDLE/Contents/Info.plist" ]]; then
  echo "A finalized app is required at $APP_BUNDLE. Run script/package_app.sh release first, or pass the signed .app path." >&2
  exit 1
fi

APP_METADATA="$(python3 - "$APP_BUNDLE/Contents/Info.plist" <<'PY'
import base64
import binascii
import plistlib
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit

with Path(sys.argv[1]).open("rb") as file:
    info = plistlib.load(file)
version = info.get("CFBundleShortVersionString", "")
build = info.get("CFBundleVersion", "")
if not all(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9._-]+", value) for value in (version, build)):
    sys.exit("The finalized app must contain valid release version and build values.")
key = info.get("SUPublicEDKey", "")
try:
    decoded = base64.b64decode(key, validate=True)
except (ValueError, binascii.Error):
    decoded = b""
if len(decoded) != 32 or decoded == bytes(32):
    sys.exit("The finalized app must contain a valid 32-byte Ed25519 public key.")
if info.get("SUVerifyUpdateBeforeExtraction") is not True:
    sys.exit("The finalized app must enable SUVerifyUpdateBeforeExtraction.")
feed = info.get("SUFeedURL", "")
url = urlsplit(feed)
if not url.hostname or url.username or url.password or url.fragment or (url.scheme != "https" and not (url.scheme == "http" and url.hostname in ("localhost", "127.0.0.1", "::1"))):
    sys.exit("The finalized app must contain an HTTPS update feed (or a local debug feed).")
print("\t".join((version, build, key, feed)))
PY
)"
IFS=$'\t' read -r VERSION BUILD PUBLIC_KEY FEED_URL <<< "$APP_METADATA"
RELEASE_TAG="${FTC_SCOUT_RELEASE_TAG:-v$VERSION}"
DOWNLOAD_PREFIX="${FTC_SCOUT_UPDATE_DOWNLOAD_URL_PREFIX:-https://github.com/Sakzyo/FTC_Event_Scout/releases/download/$RELEASE_TAG/}"
python3 - "$DOWNLOAD_PREFIX" "$FEED_URL" <<'PY'
import sys
from urllib.parse import urlsplit

download, feed = (urlsplit(value) for value in sys.argv[1:])
loopbacks = ("localhost", "127.0.0.1", "::1")
local_test = feed.scheme == "http" and feed.hostname in loopbacks and download.scheme == "http" and download.hostname in loopbacks
if not download.hostname or download.username or download.password or download.query or download.fragment or (download.scheme != "https" and not local_test):
    sys.exit("Update download URLs must use HTTPS; local debug feeds may explicitly use HTTP localhost downloads.")
PY
DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX%/}/"

for tool in generate_keys generate_appcast sign_update; do
  if [[ ! -x "$SPARKLE_TOOLS/$tool" ]]; then
    echo "Sparkle's $tool is missing. Resolve the Sparkle Swift package before packaging updates." >&2
    exit 1
  fi
done
if ! KEYCHAIN_PUBLIC_KEY="$("$SPARKLE_TOOLS/generate_keys" --account "$KEY_ACCOUNT" -p)"; then
  echo "The Sparkle signing key is unavailable in Keychain account $KEY_ACCOUNT. Run generate_keys with that account on the release Mac." >&2
  exit 1
fi
if [[ "$KEYCHAIN_PUBLIC_KEY" != "$PUBLIC_KEY" ]]; then
  echo "The Sparkle signing key does not match the finalized app's SUPublicEDKey. Use the matching Keychain account." >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
if [[ -n "${FTC_SCOUT_NOTARYTOOL_PROFILE:-}" ]]; then
  # package_app.sh notarizes and staples before this archive is signed.
  xcrun stapler validate "$APP_BUNDLE"
fi

mkdir -p "$BUILD_ROOT" "$UPDATE_DIR"
STAGING_DIR="$(mktemp -d "$BUILD_ROOT/sparkle-update.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ARCHIVE_NAME="FTC-Event-Scout-$VERSION.zip"
ARCHIVE_PATH="$STAGING_DIR/$ARCHIVE_NAME"
APPCAST_PATH="$STAGING_DIR/appcast.xml"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE_PATH"
"$SPARKLE_TOOLS/generate_appcast" \
  --account "$KEY_ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --versions "$BUILD" \
  --maximum-deltas 0 \
  -o "$APPCAST_PATH" \
  "$STAGING_DIR"

SIGNATURE="$(python3 - "$APPCAST_PATH" "$ARCHIVE_PATH" "$DOWNLOAD_PREFIX$ARCHIVE_NAME" "$BUILD" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

appcast, archive, expected_url, expected_build = sys.argv[1:]
namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
root = ET.parse(appcast).getroot()
items = root.findall("./channel/item")
if len(items) != 1 or items[0].findtext(namespace + "version") != expected_build:
    sys.exit("Sparkle did not generate an appcast for the finalized app's build.")
enclosure = items[0].find("enclosure")
if enclosure is None or enclosure.get("url") != expected_url or enclosure.get("length") != str(Path(archive).stat().st_size):
    sys.exit("Sparkle generated an unexpected update URL or archive length.")
signature = enclosure.get(namespace + "edSignature", "")
if not signature:
    sys.exit("Sparkle did not sign the update archive. No release artifacts were published.")
print(signature)
PY
)"
"$SPARKLE_TOOLS/sign_update" --account "$KEY_ACCOUNT" --verify "$ARCHIVE_PATH" "$SIGNATURE"
mv -f "$ARCHIVE_PATH" "$UPDATE_DIR/$ARCHIVE_NAME"
mv -f "$APPCAST_PATH" "$UPDATE_DIR/appcast.xml"
echo "Packaged $UPDATE_DIR/$ARCHIVE_NAME"
echo "Appcast $UPDATE_DIR/appcast.xml"
echo "Upload both files to GitHub Release $RELEASE_TAG."
