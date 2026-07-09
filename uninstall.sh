#!/bin/bash
#
# uninstall.sh — cleanly removes DisplayWatchdogToggle: stops and unloads
# the LaunchAgent, deletes the plist and the installed app. Your saved
# layout/state/log in ~/.display-manager are left in place unless you
# explicitly confirm removing them too.
#
set -euo pipefail

APP_NAME="DisplayWatchdogToggle"
APP_DEST="$HOME/Applications/$APP_NAME.app"
AGENT_LABEL="com.polerix.display-watchdog"
PLIST_DEST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
DISPLAY_MANAGER_DIR="$HOME/.display-manager"

echo "== DisplayWatchdogToggle uninstaller =="
echo

if [ -d "$APP_DEST" ]; then
    echo "If '$APP_NAME' has 'Launch at Login' enabled, please open it and turn that"
    echo "off from its menu first — there's no reliable way to do that from here"
    echo "once the app bundle is removed."
    read -r -p "Continue with uninstall? [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo "Quitting the app if it's running..."
pkill -f "$APP_DEST/Contents/MacOS/$APP_NAME" 2>/dev/null || true

echo "Stopping the watchdog LaunchAgent..."
launchctl bootout "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || true

if [ -f "$PLIST_DEST" ]; then
    rm -f "$PLIST_DEST"
    echo "Removed $PLIST_DEST"
fi

if [ -d "$APP_DEST" ]; then
    rm -rf "$APP_DEST"
    echo "Removed $APP_DEST"
fi

echo
if [ -d "$DISPLAY_MANAGER_DIR" ]; then
    read -r -p "Also delete your saved layout, state, and log in $DISPLAY_MANAGER_DIR? [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        rm -rf "$DISPLAY_MANAGER_DIR"
        echo "Removed $DISPLAY_MANAGER_DIR"
    else
        echo "Left $DISPLAY_MANAGER_DIR in place."
    fi
fi

echo
echo "== Done =="
