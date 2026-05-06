#!/bin/bash
# package.sh — build heu and produce a distributable DMG
# Usage: bash scripts/package.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
VERSION="1.0"
APP_NAME="heu"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

cd "$ROOT"

echo "==> Building heu v${VERSION}..."
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release > /dev/null
cmake --build build -j"$(sysctl -n hw.logicalcpu)"

echo "==> Creating app bundle..."
APP="dist/${APP_NAME}.app"
rm -rf dist
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"

cp build/heu               "${APP}/Contents/MacOS/heu"
cp src/Info.plist          "${APP}/Contents/Info.plist"
chmod +x "${APP}/Contents/MacOS/heu"

echo "==> Ad-hoc signing..."
codesign --force --sign - --deep "${APP}"

echo "==> Creating DMG..."
STAGING="dist/_dmg_staging"
mkdir -p "$STAGING"
cp -R "${APP}" "$STAGING/"
# Symlink to /Applications for drag-install UI
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "heu" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "dist/${DMG_NAME}"

rm -rf "$STAGING"

echo ""
echo "✓ dist/${DMG_NAME} ready"
echo ""
echo "To distribute:"
echo "  1. Upload dist/${DMG_NAME} to GitHub Releases"
echo "  2. Users: mount DMG → drag heu to Applications → right-click → Open (first time)"
echo "  3. Grant Microphone, Accessibility, and Automation permissions when prompted"
