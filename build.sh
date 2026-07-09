#!/bin/bash
# Dev-loop rebuild: compiles Sources/main.swift and reassembles the .app
# bundle in ~/Applications, without touching the LaunchAgent or any live
# ~/.display-manager state. For a first-time install (which also migrates
# the LaunchAgent and its bundled scripts), use install.sh instead.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="DisplayWatchdogToggle"
DEST="$HOME/Applications/$APP_NAME.app"

rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources/Scripts"

cp "$DIR/Resources/Info.plist" "$DEST/Contents/Info.plist"
cp "$DIR/Resources/WatchDog_ON.png" "$DEST/Contents/Resources/WatchDog_ON.png"
cp "$DIR/Resources/WatchDog_OFF.png" "$DEST/Contents/Resources/WatchDog_OFF.png"
cp "$DIR/Resources/WatchDog_Notify.png" "$DEST/Contents/Resources/WatchDog_Notify.png"

cp "$DIR/Scripts/display-watchdog.sh" "$DEST/Contents/Resources/Scripts/display-watchdog.sh"
cp "$DIR/Scripts/save-display-config.sh" "$DEST/Contents/Resources/Scripts/save-display-config.sh"
cp "$DIR/Scripts/restore-display-config.sh" "$DEST/Contents/Resources/Scripts/restore-display-config.sh"
chmod +x "$DEST/Contents/Resources/Scripts/"*.sh

swiftc -O "$DIR/Sources/main.swift" -o "$DEST/Contents/MacOS/$APP_NAME"

echo "Built $DEST"
