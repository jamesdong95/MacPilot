#!/usr/bin/env bash
#
# Build and package MacPilotDemo as a DMG for local distribution.
#
# By default this produces an UNSIGNED (ad-hoc) build: Gatekeeper will warn
# when opening it. To produce a signed + notarized release instead, set the
# environment variables below and the script will codesign and staple:
#
#   DEVELOPER_ID_APPLICATION   e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE             a notarytool profile already stored via
#                              `xcrun notarytool store-credentials`
#
#   NOTARY_PROFILE="macpilot" DEVELOPER_ID_APPLICATION="Developer ID Application: …" \
#     scripts/package.sh
#
# See docs/SIGNING.md for the full one-time setup.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="$(python3 -c 'from macpilot import __version__; print(__version__)' 2>/dev/null || echo 0.4.0)"
APP_NAME="MacPilotDemo"
DERIVED="/tmp/MacPilotDerivedData-release-${VERSION}"
DIST="${REPO_ROOT}/dist"
STAGING="$(mktemp -d /tmp/macpilot-staging.XXXXXX)"
trap 'rm -rf "${STAGING}"' EXIT

echo "==> Building ${APP_NAME} ${VERSION} (Release)…"
xcodebuild \
  -project "${REPO_ROOT}/MacPilotDemo/${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED}" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
[ -d "${APP}" ] || { echo "error: app bundle not found at ${APP}"; exit 1; }

if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
  echo "==> Codesigning with ${DEVELOPER_ID_APPLICATION}…"
  codesign --force --deep --options runtime \
    --sign "${DEVELOPER_ID_APPLICATION}" \
    --timestamp \
    "${APP}"

  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing…"
    ditto -c -k --keepParent "${APP}" "${STAGING}/${APP_NAME}.zip"
    xcrun notarytool submit "${STAGING}/${APP_NAME}.zip" \
      --keychain-profile "${NOTARY_PROFILE}" \
      --wait
    xcrun stapler staple "${APP}"
    rm -f "${STAGING}/${APP_NAME}.zip"
  fi
else
  echo "==> Skipping codesign (no DEVELOPER_ID_APPLICATION set) — unsigned build."
fi

echo "==> Staging DMG…"
mkdir -p "${DIST}"
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"
rm -f "${DMG}"
hdiutil create -volname "MacPilot" -srcfolder "${STAGING}" -ov -format UDZO "${DMG}"

echo "==> Done: ${DMG}"
shasum -a 256 "${DMG}"
