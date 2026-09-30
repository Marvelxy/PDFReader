#!/bin/sh
# Assembles PDFReader.app from the SwiftPM build output and ad-hoc signs it.
#
# Why a bundle: on macOS Tahoe cursor changes (resize handle, I-beam, …)
# only render when running as a proper `.app`. A raw `swift run` binary
# runs fine otherwise, but the pointer stays an arrow everywhere.
#
# Usage:
#   scripts/make-app.sh [debug|release]   # default: debug
#   open .build/app/PDFReader.app
set -eu
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP_DIR=".build/app/PDFReader.app"
BIN=".build/debug/PDFReader"
if [ "$CONFIG" = "release" ]; then
    BIN=".build/release/PDFReader"
fi

swift build -c "$CONFIG" --product PDFReader

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN" "$APP_DIR/Contents/MacOS/PDFReader"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>PDFReader</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.pdfreader</string>
	<key>CFBundleName</key>
	<string>PDFReader</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
echo "Built $APP_DIR"
