#!/bin/bash
#
# display-watchdog.sh
# Runs as a daemon to detect and restore display configuration
#

# Intentionally set -u only, not -e/pipefail: this is a long-running loop
# where a single failed sub-check (e.g. displayplacer hiccups for one poll)
# should be logged and skipped, not take the whole daemon down. Every
# fallible call below is guarded explicitly (|| true, explicit checks).
set -u

CONFIG_DIR="$HOME/.display-manager"
CONFIG_FILE="$CONFIG_DIR/saved-config.txt"
STATE_FILE="$CONFIG_DIR/previous-state.txt"
LOG_FILE="$CONFIG_DIR/watchdog.log"
LOG_MAX_BYTES=$((5 * 1024 * 1024))  # 5 MB
POLL_INTERVAL=5  # seconds
DEBOUNCE_POLLS=2
RESTORE_COOLDOWN_SEC=60
PENDING_STATE=""
PENDING_COUNT=0
LAST_RESTORE_EPOCH=0
COOLDOWN_LOGGED=0

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR" 2>/dev/null || true

# Rotate the log at startup if it's grown past LOG_MAX_BYTES, so a
# long-running install doesn't accumulate an unbounded log file.
if [ -f "$LOG_FILE" ]; then
    LOG_SIZE=$(stat -f %z "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$LOG_SIZE" -gt "$LOG_MAX_BYTES" ]; then
        mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || true
    fi
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

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
    log "Error: displayplacer not found. Install with: brew install displayplacer"
    exit 1
fi

get_current_state() {
    "$DISPLAYPLACER_BIN" list | awk '
        /^Resolution:/ { res=$2; next }
        /^Origin:/ {
            origin=$2
            gsub(/\r/, "", origin)
            next
        }
        /^Enabled:/ {
            enabled=$2
            if (res != "" && origin != "" && enabled != "") {
                print res "|" origin "|" enabled
            }
            res=""; origin=""; enabled=""
        }
    ' | sort | md5 -q
}

restore_if_needed() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return
    fi

    # Get displayplacer command
    DISPLAY_CMD="$(sed -n 's/^DISPLAYPLACER_CMD=//p' "$CONFIG_FILE" | head -n1)"

    if [ -z "$DISPLAY_CMD" ]; then
        return
    fi
    if [ "$DISPLAY_CMD" = "displayplacer" ] || [[ "$DISPLAY_CMD" != *"id:"* ]]; then
        log "Saved restore command is incomplete; skipping restore cycle."
        return
    fi

    CURRENT_STATE="$(get_current_state || true)"
    if [ -z "$CURRENT_STATE" ]; then
        log "Could not determine current display state; skipping this cycle."
        return
    fi

    if [ -f "$STATE_FILE" ]; then
        PREVIOUS_STATE="$(cat "$STATE_FILE")"

        if [ "$CURRENT_STATE" != "$PREVIOUS_STATE" ]; then
            if [ "$CURRENT_STATE" = "$PENDING_STATE" ]; then
                PENDING_COUNT=$((PENDING_COUNT + 1))
            else
                PENDING_STATE="$CURRENT_STATE"
                PENDING_COUNT=1
                log "Display change observed; waiting for debounce (${PENDING_COUNT}/${DEBOUNCE_POLLS})."
            fi

            if [ "$PENDING_COUNT" -lt "$DEBOUNCE_POLLS" ]; then
                return
            fi

            NOW_EPOCH="$(date +%s)"
            if [ $((NOW_EPOCH - LAST_RESTORE_EPOCH)) -lt "$RESTORE_COOLDOWN_SEC" ]; then
                if [ "$COOLDOWN_LOGGED" -eq 0 ]; then
                    log "Change confirmed but in cooldown; skipping restore attempts."
                    COOLDOWN_LOGGED=1
                fi
                return
            fi

            log "Display configuration change detected!"
            log "Restoring..."

            # Small delay to let system settle
            sleep 1

            if /bin/bash -lc "$DISPLAY_CMD"; then
                log "Display configuration restored."
                # Update state
                get_current_state > "$STATE_FILE"
                LAST_RESTORE_EPOCH="$(date +%s)"
                PENDING_STATE=""
                PENDING_COUNT=0
                COOLDOWN_LOGGED=0
            else
                log "Restore command failed."
                LAST_RESTORE_EPOCH="$(date +%s)"
                PENDING_STATE=""
                PENDING_COUNT=0
                COOLDOWN_LOGGED=0
            fi
        else
            PENDING_STATE=""
            PENDING_COUNT=0
            COOLDOWN_LOGGED=0
        fi
    else
        # First run - just save state
        echo "$CURRENT_STATE" > "$STATE_FILE"
    fi
}

log "Display watchdog started (PID: $$)"

# Save initial state
INITIAL_STATE="$(get_current_state || true)"
if [ -z "$INITIAL_STATE" ]; then
    log "Could not determine initial display state; exiting."
    exit 1
fi
echo "$INITIAL_STATE" > "$STATE_FILE"

# Main loop
while true; do
    restore_if_needed
    sleep $POLL_INTERVAL
done
