#!/bin/bash
#
# save-display-config.sh
# Saves the current display configuration to a file for restoration
#

set -u

CONFIG_DIR="$HOME/.display-manager"
CONFIG_FILE="$CONFIG_DIR/saved-config.txt"
TMP_FILE="$CONFIG_DIR/saved-config.txt.tmp"

resolve_displayplacer() {
    if [ -x "/opt/homebrew/bin/displayplacer" ]; then
        echo "/opt/homebrew/bin/displayplacer"
        return 0
    fi
    if [ -x "/usr/local/bin/displayplacer" ]; then
        echo "/usr/local/bin/displayplacer"
        return 0
    fi
    if command -v displayplacer >/dev/null 2>&1; then
        command -v displayplacer
        return 0
    fi
    return 1
}

DISPLAYPLACER_BIN="$(resolve_displayplacer || true)"
if [ -z "$DISPLAYPLACER_BIN" ]; then
    echo "Error: displayplacer not found. Install it with: brew install displayplacer"
    exit 1
fi

mkdir -p "$CONFIG_DIR"

# Get current display configuration
DISPLAY_LIST="$("$DISPLAYPLACER_BIN" list)"

# Extract and save the displayplacer command.
# displayplacer prints a blank line between the marker text and the command.
DISPLAY_CMD="$(
    printf "%s\n" "$DISPLAY_LIST" | awk '
        /Execute the command below/ { seen=1; next }
        seen && NF { print; exit }
    '
)"
if [ -z "$DISPLAY_CMD" ] || [ "$DISPLAY_CMD" = "displayplacer" ] || [[ "$DISPLAY_CMD" != *"id:"* ]]; then
    echo "Error: displayplacer did not return a complete restore command."
    echo "Run this again while all target displays are connected."
    exit 1
fi

# Persist absolute binary path so launchd PATH does not matter.
DISPLAY_CMD="${DISPLAY_CMD/#displayplacer/$DISPLAYPLACER_BIN}"

# Allow partial restore when one screen is missing during KVM switches.
DISPLAY_CMD="$(printf "%s\n" "$DISPLAY_CMD" | sed -E 's/ degree:([0-9]+)"/ degree:\1 quiet:true"/g')"

echo "# Display configuration saved $(date)" > "$TMP_FILE"
printf "%s\n" "$DISPLAY_LIST" >> "$TMP_FILE"
echo "" >> "$TMP_FILE"
echo "# Restore command:" >> "$TMP_FILE"
echo "DISPLAYPLACER_CMD=$DISPLAY_CMD" >> "$TMP_FILE"

mv "$TMP_FILE" "$CONFIG_FILE"

echo "Display configuration saved to $CONFIG_FILE"
echo ""
echo "To restore: ./restore-display-config.sh"
