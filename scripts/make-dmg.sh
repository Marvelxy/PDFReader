#!/bin/sh
# Creates a distributable DMG from a bundled .app, with a drag-to-Applications
# symlink. The app built by scripts/make-app.sh is universal (arm64+x86_64)
# when the toolchain supports it, so one DMG serves both architectures.
#
# Usage:
#   scripts/make-dmg.sh <path-to-app> [output.dmg] [VolumeName]
set -eu
APP="${1:?usage: make-dmg.sh <PDFReader.app> [output.dmg] [VolumeName]}"
OUT="${2:-PDFReader-macOS-universal.dmg}"
VOLUME="${3:-PDFReader}"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT INT TERM
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
echo "Created $OUT"
