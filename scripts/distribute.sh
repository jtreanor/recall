#!/usr/bin/env bash
# Builds, signs, and packages Recall for direct distribution.
#
# Ad-hoc mode (default, no Apple Developer Program required):
#   ./scripts/distribute.sh
#
# Notarized mode (requires paid Apple Developer Program + Developer ID cert):
#   TEAM_ID=XXXXXXXXXX APPLE_ID=you@example.com APP_PASSWORD=xxxx-xxxx-xxxx-xxxx \
#     ./scripts/distribute.sh --notarize

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
APP_NAME="Recall"
BUNDLE_ID="com.recall.app"
VERSION="${VERSION:-0.1.0}"
BUILD_DIR="$(cd "$(dirname "$0")/.." && pwd)/build/dist"
APP_PATH="${BUILD_DIR}/app/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
ENTITLEMENTS="$(cd "$(dirname "$0")/.." && pwd)/Recall/Recall.entitlements"

NOTARIZE=false
if [[ "${1:-}" == "--notarize" ]]; then
  NOTARIZE=true
  : "${TEAM_ID:?TEAM_ID must be set for notarization}"
  : "${APPLE_ID:?APPLE_ID must be set for notarization}"
  : "${APP_PASSWORD:?APP_PASSWORD must be set for notarization}"
  SIGN_IDENTITY="Developer ID Application"
else
  SIGN_IDENTITY="-"  # ad-hoc
fi

# ── 1. Build ──────────────────────────────────────────────────────────────────
echo "▸ Building ${APP_NAME} (Release)…"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/app"

xcodebuild build \
  -project "$(cd "$(dirname "$0")/.." && pwd)/Recall.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  CONFIGURATION_BUILD_DIR="${BUILD_DIR}/app" \
  CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="${TEAM_ID:-}" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  ONLY_ACTIVE_ARCH=NO \
  2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" || true

if [[ ! -d "${APP_PATH}" ]]; then
  echo "✗ Build failed — ${APP_PATH} not found"
  exit 1
fi
echo "  ✓ Built ${APP_PATH}"

# ── 2. Re-sign with clean entitlements (strips debug get-task-allow) ──────────
echo "▸ Signing with clean entitlements…"
codesign --deep --force --sign "${SIGN_IDENTITY}" \
  -o runtime \
  --entitlements "${ENTITLEMENTS}" \
  --timestamp=none \
  "${APP_PATH}"
echo "  ✓ Signed"

# ── 3. Verify signature ───────────────────────────────────────────────────────
echo "▸ Verifying signature…"
codesign --verify --deep --strict "${APP_PATH}"
echo "  ✓ Signature valid"
codesign -dv "${APP_PATH}" 2>&1 | grep -E "(Identifier|TeamIdentifier|Signature|flags)"

# ── 4. Create DMG ─────────────────────────────────────────────────────────────
echo "▸ Creating DMG…"
TMP_DMG="${BUILD_DIR}/tmp_rw.dmg"

# Create writable DMG large enough for the app
APP_SIZE_MB=$(du -sm "${APP_PATH}" | cut -f1)
DMG_SIZE_MB=$(( APP_SIZE_MB + 10 ))

hdiutil create \
  -srcfolder "${APP_PATH}" \
  -volname "${APP_NAME}" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,b=16" \
  -format UDRW \
  -size "${DMG_SIZE_MB}m" \
  "${TMP_DMG}"

# Mount it, add /Applications symlink
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "${TMP_DMG}" \
  | grep "/Volumes" | awk '{print $NF}')
ln -sf /Applications "${MOUNT_DIR}/Applications"

# Unmount and convert to compressed read-only
hdiutil detach "${MOUNT_DIR}" -quiet
hdiutil convert "${TMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}"
rm -f "${TMP_DMG}"

echo "  ✓ Created ${DMG_PATH}"

# ── 5. Notarize + staple (skipped in ad-hoc mode) ─────────────────────────────
if [[ "${NOTARIZE}" == true ]]; then
  echo "▸ Submitting to Apple notary service…"
  xcrun notarytool submit "${DMG_PATH}" \
    --apple-id "${APPLE_ID}" \
    --password "${APP_PASSWORD}" \
    --team-id "${TEAM_ID}" \
    --wait

  echo "▸ Stapling notarization ticket…"
  xcrun stapler staple "${DMG_PATH}"
  echo "  ✓ Stapled"

  echo "▸ Verifying Gatekeeper acceptance…"
  spctl --assess --type open --context context:primary-signature -v "${DMG_PATH}"
  echo "  ✓ Gatekeeper accepts DMG"
else
  echo ""
  echo "  ℹ Ad-hoc build complete. Users must right-click → Open on first launch,"
  echo "    or run: xattr -dr com.apple.quarantine Recall.app"
  echo "  ℹ To notarize later: TEAM_ID=… APPLE_ID=… APP_PASSWORD=… ./scripts/distribute.sh --notarize"
fi

echo ""
echo "✓ Done: ${DMG_PATH}"
