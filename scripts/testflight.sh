#!/usr/bin/env bash
#
# Archive House Music (iOS + embedded Watch app) and upload to TestFlight.
#
# Usage: bash scripts/testflight.sh
#
# Requires deploy/.env with:
#   APP_STORE_CONNECT_API_KEY_ID
#   APP_STORE_CONNECT_API_ISSUER_ID
#   APP_STORE_CONNECT_API_KEY_PATH   (path to the .p8)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE="$BUILD_DIR/HouseMusic.xcarchive"
ENV_FILE="$ROOT_DIR/deploy/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi
: "${APP_STORE_CONNECT_API_KEY_ID:?Set APP_STORE_CONNECT_API_KEY_ID}"
: "${APP_STORE_CONNECT_API_ISSUER_ID:?Set APP_STORE_CONNECT_API_ISSUER_ID}"
: "${APP_STORE_CONNECT_API_KEY_PATH:?Set APP_STORE_CONNECT_API_KEY_PATH}"
KEY_PATH="${APP_STORE_CONNECT_API_KEY_PATH/#\~/$HOME}"

echo "==> Regenerating project"
(cd "$ROOT_DIR" && xcodegen generate)

echo "==> Archiving"
xcodebuild -project "$ROOT_DIR/HouseMusic.xcodeproj" \
  -scheme HouseMusic \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  clean archive \
  -allowProvisioningUpdates \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID" \
  -authenticationKeyPath "$KEY_PATH"

echo "==> Exporting and uploading to TestFlight"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>teamID</key><string>86H54WCPYP</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$BUILD_DIR/export" \
  -allowProvisioningUpdates \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID" \
  -authenticationKeyPath "$KEY_PATH"

echo "==> Uploaded. Check App Store Connect > TestFlight."
