#!/bin/bash
#
# restore-display-config.sh
# Restores the saved display configuration
#

set -u

CONFIG_DIR="$HOME/.display-manager"
CONFIG_FILE="$CONFIG_DIR/saved-config.txt"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "No saved configuration found. Run save-display-config.sh first."
    exit 1
fi

# Extract the restore command
DISPLAY_CMD="$(sed -n 's/^DISPLAYPLACER_CMD=//p' "$CONFIG_FILE" | head -n1)"

if [ -z "$DISPLAY_CMD" ]; then
    echo "Could not find restore command in config file."
    exit 1
fi
if [ "$DISPLAY_CMD" = "displayplacer" ] || [[ "$DISPLAY_CMD" != *"id:"* ]]; then
    echo "Saved restore command is incomplete. Re-run save-display-config.sh with displays connected."
    exit 1
fi

echo "Restoring display configuration..."
echo "$DISPLAY_CMD"
if ! /bin/bash -lc "$DISPLAY_CMD"; then
    echo "Restore command failed."
    exit 1
fi

echo "Display configuration restored."
