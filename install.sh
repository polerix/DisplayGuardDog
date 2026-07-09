#!/bin/bash
#
# install.sh — builds DisplayWatchdogToggle.app and installs it, including
# the LaunchAgent that runs the bundled watchdog script. Safe to re-run
# (e.g. to upgrade): it replaces the app and LaunchAgent in place while
# leaving ~/.display-manager (your saved layout, state, and log) untouched.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="DisplayWatchdogToggle"
APP_DEST="$HOME/Applications/$APP_NAME.app"
AGENT_LABEL="com.polerix.display-watchdog"
PLIST_DEST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
DISPLAY_MANAGER_DIR="$HOME/.display-manager"

echo "== DisplayWatchdogToggle installer =="
echo

# --- 1. Check for Swift toolchain -------------------------------------
if ! command -v swiftc >/dev/null 2>&1; then
    echo "Error: swiftc not found. Install the Xcode Command Line Tools first:"
    echo "    xcode-select --install"
    exit 1
fi

# --- 2. Check for displayplacer, offer to install via Homebrew --------
resolve_displayplacer() {
    if [ -x "/opt/homebrew/bin/displayplacer" ]; then
        echo "/opt/homebrew/bin/displayplacer"; return 0
    fi
    if [ -x "/usr/local/bin/displayplacer" ]; then
        echo "/usr/local/bin/displayplacer"; return 0
    fi
    if command -v displayplacer >/dev/null 2>&1; then
        command -v displayplacer; return 0
    fi
    return 1
}

if ! resolve_displayplacer >/dev/null; then
    echo "displayplacer is required (it does the actual display arrangement work) but isn't installed."
    if command -v brew >/dev/null 2>&1; then
        read -r -p "Install it now with 'brew install displayplacer'? [y/N] " reply
        if [[ "$reply" =~ ^[Yy]$ ]]; then
            brew install displayplacer
        else
            echo "Skipping. You can install it later with: brew install displayplacer"
        fi
    else
        echo "Homebrew isn't installed either. Install Homebrew (https://brew.sh), then:"
        echo "    brew install displayplacer"
        echo "Continuing installation — the app will still install, but the watchdog"
        echo "won't function until displayplacer is available."
    fi
fi
echo

# --- 3. Remember current on/off + login-item state (for migration) ----
WAS_RUNNING=0
if launchctl list "$AGENT_LABEL" >/dev/null 2>&1; then
    WAS_RUNNING=1
fi

# --- 4. Build the app ---------------------------------------------------
echo "Building $APP_NAME..."
mkdir -p "$APP_DEST/Contents/MacOS" "$APP_DEST/Contents/Resources/Scripts"

cp "$DIR/Resources/Info.plist" "$APP_DEST/Contents/Info.plist"
cp "$DIR/Resources/WatchDog_ON.png" "$APP_DEST/Contents/Resources/WatchDog_ON.png"
cp "$DIR/Resources/WatchDog_OFF.png" "$APP_DEST/Contents/Resources/WatchDog_OFF.png"
cp "$DIR/Resources/WatchDog_Notify.png" "$APP_DEST/Contents/Resources/WatchDog_Notify.png"

cp "$DIR/Scripts/display-watchdog.sh" "$APP_DEST/Contents/Resources/Scripts/display-watchdog.sh"
cp "$DIR/Scripts/save-display-config.sh" "$APP_DEST/Contents/Resources/Scripts/save-display-config.sh"
cp "$DIR/Scripts/restore-display-config.sh" "$APP_DEST/Contents/Resources/Scripts/restore-display-config.sh"
chmod +x "$APP_DEST/Contents/Resources/Scripts/"*.sh

swiftc -O "$DIR/Sources/main.swift" -o "$APP_DEST/Contents/MacOS/$APP_NAME"
echo "Built $APP_DEST"
echo

# --- 5. Migrate the LaunchAgent to point at the bundled script --------
BUNDLED_WATCHDOG_SCRIPT="$APP_DEST/Contents/Resources/Scripts/display-watchdog.sh"

if [ "$WAS_RUNNING" -eq 1 ]; then
    echo "Stopping existing watchdog (will restart it against the new install)..."
    launchctl bootout "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || true
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_DEST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BUNDLED_WATCHDOG_SCRIPT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$DISPLAY_MANAGER_DIR/watchdog.log</string>
    <key>StandardErrorPath</key>
    <string>$DISPLAY_MANAGER_DIR/watchdog.log</string>
</dict>
</plist>
EOF

echo "Installed LaunchAgent: $PLIST_DEST"
echo "  -> points at: $BUNDLED_WATCHDOG_SCRIPT"

if [ "$WAS_RUNNING" -eq 1 ]; then
    launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"
    echo "Watchdog restarted (it was running before the install)."
else
    echo "Watchdog left off (it wasn't running before the install)."
    echo "Turn it on any time from the menu bar app's menu."
fi
echo

# --- 6. Note superseded legacy scripts, if present ----------------------
LEGACY_DIR="$HOME/bin"
if [ -f "$LEGACY_DIR/display-watchdog.sh" ]; then
    echo "Note: $LEGACY_DIR/{display-watchdog,save-display-config,restore-display-config}.sh"
    echo "are now superseded by the copies bundled inside the app and are safe to remove"
    echo "manually whenever you like. They were left untouched by this installer."
    echo
fi

echo "Your saved layout, state, and log in $DISPLAY_MANAGER_DIR were left untouched."
echo
echo "== Done =="
echo "Open $APP_DEST to use the menu bar app."
