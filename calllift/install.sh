#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 nuschpl. CallLift: https://github.com/nuschpl/CallLift
# Install / remove CallLift as a login item (LaunchAgent).
#   ./install.sh               build, install ~/Applications/CallLift.app and start it at every login
#   ./install.sh --uninstall   stop it and remove the login item (the app itself stays in ~/Applications)
# Quitting CallLift from its menu really quits it until next login; a crash restarts it automatically.
set -e
SRC="${0:A:h}"
LABEL="io.github.nuschpl.CallLift"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
BIN="$HOME/Applications/CallLift.app/Contents/MacOS/CallLift"

unload() {
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  for i in {1..20}; do launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || break; sleep 0.5; done
}

if [[ ${1:-} == --uninstall ]]; then
  unload; pkill -x CallLift 2>/dev/null || true; rm -f "$PLIST"
  echo "Removed login item. To delete the app too: rm -rf ~/Applications/CallLift.app"
  exit 0
fi

"$SRC/build.sh"
unload
pkill -x CallLift 2>/dev/null && sleep 1 || true
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- CallLift: boosts the mic (+gain, limiter) into a virtual device for call apps. Source: $SRC
	     Remove: $SRC/install.sh --uninstall -->
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key><array><string>$BIN</string></array>
	<key>LimitLoadToSessionType</key><string>Aqua</string>
	<key>ProcessType</key><string>Interactive</string>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
	<key>ThrottleInterval</key><integer>30</integer>
	<key>StandardOutPath</key><string>/dev/null</string>
	<key>StandardErrorPath</key><string>$HOME/Library/Logs/CallLift.stderr.log</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Installed login item $LABEL -> $BIN"
