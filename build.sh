#!/usr/bin/env bash
# Compila o app num bundle .app usando swiftc diretamente.
# (O SwiftPM/`swift run` está quebrado nesta instalação de CommandLineTools,
#  então evitamos o Package.swift de propósito.)
set -euo pipefail
cd "$(dirname "$0")"

APP="CafeNoNotch.app"
MACOS="$APP/Contents/MacOS"
BIN="$MACOS/CafeNoNotch"
TARGET="arm64-apple-macosx14.0"

echo "→ compilando…"
rm -rf "$APP"
mkdir -p "$MACOS"
swiftc Sources/CafeNoNotch/*.swift -o "$BIN" -target "$TARGET" -O

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Café no Notch</string>
    <key>CFBundleDisplayName</key>     <string>Café no Notch</string>
    <key>CFBundleIdentifier</key>      <string>com.vitorbellini.cafenonotch</string>
    <key>CFBundleExecutable</key>      <string>CafeNoNotch</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.2.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>MVP — protótipo</string>
</dict>
</plist>
PLIST

echo "✓ pronto: $APP"
echo "  abrir:   open $APP"
echo "  testar:  ./$BIN --brew   (acende o halo já no lançamento)"
