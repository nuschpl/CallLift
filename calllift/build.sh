#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 nuschpl. CallLift: https://github.com/nuschpl/CallLift
# Build CallLift.app and install it to ~/Applications (outside Desktop: background jobs can't read ~/Desktop).
#   ./build.sh            build + install (quits a running CallLift first)
set -e
SRC="${0:A:h}"
APP="$HOME/Applications/CallLift.app"
BIN="$APP/Contents/MacOS/CallLift"
mkdir -p "$SRC/build"
swiftc -swift-version 5 -O -target arm64-apple-macos15.0 "$SRC/Audio.swift" "$SRC/Controller.swift" "$SRC/App.swift" "$SRC/StatsWindow.swift" "$SRC/HelpWindow.swift" "$SRC/main.swift" -o "$SRC/build/CallLift"

pkill -x CallLift 2>/dev/null && sleep 1 || true
mkdir -p "$APP/Contents/MacOS"
cp "$SRC/build/CallLift" "$BIN"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.nuschpl.CallLift</string>
  <key>CFBundleName</key><string>CallLift</string>
  <key>CFBundleDisplayName</key><string>CallLift</string>
  <key>CFBundleExecutable</key><string>CallLift</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>CallLift reads your microphone, raises its level and passes it to your call app through a virtual audio device (BlackHole 2ch). Nothing is recorded or sent anywhere else.</string>
</dict></plist>
EOF
# ad-hoc signature (local use only); keeps a stable identity for the microphone permission
codesign --force --sign - --identifier io.github.nuschpl.CallLift "$APP"
codesign --verify "$APP" && echo "Built and signed: $APP"
