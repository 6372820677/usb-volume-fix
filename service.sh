#!/system/bin/sh
# service.sh - Start USB Volume Fix v2 watchdog
# The watchdog monitors USB DAC presence and only starts/stops the daemon as needed

CONF_DIR=/data/adb/service.d/usbvol_fix_v2
MODPATH=/data/adb/modules/usb_volume_fix_v2
WATCHDOG_BIN=${MODPATH}/system/bin/usbvol_fix_v2_watchdog.sh
DAEMON_BIN=${MODPATH}/system/bin/usbvol_fix_v2_daemon.sh
DISABLE_FILE=$CONF_DIR/.usbvol_fix_v2_disabled

# Create config dir
mkdir -p "$CONF_DIR" 2>/dev/null

# Check if module is disabled
if [ -f "$DISABLE_FILE" ]; then
    echo "USB Volume Fix v2 disabled"
    exit 0
fi

# Verify watchdog exists
if [ ! -x "$WATCHDOG_BIN" ]; then
    echo "USB Volume Fix v2: watchdog script missing"
    exit 1
fi

# Kill existing watchdog (not the daemon - watchdog handles that)
WATCHDOG_PID_FILE=$CONF_DIR/.usbvol_fix_v2_watchdog.pid
if [ -f "$WATCHDOG_PID_FILE" ]; then
    OLD_PID=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
        sleep 0.5
        kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f "$WATCHDOG_PID_FILE"
fi

# Also kill any existing daemon (watchdog will restart it if USB is present)
DAEMON_PID_FILE=$CONF_DIR/.usbvol_fix_v2_daemon.pid
if [ -f "$DAEMON_PID_FILE" ]; then
    OLD_PID=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
        sleep 0.5
        kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f "$DAEMON_PID_FILE"
fi

# Kill any lingering daemon/watchdog processes (safe patterns; do not match this script's own path)
pkill -f "usbvol_fix_v2_daemon" 2>/dev/null
pkill -f "usbvol_fix_v2_watchdog" 2>/dev/null

# Start watchdog detached
setsid "$WATCHDOG_BIN" </dev/null >/dev/null 2>&1 &

# Wait briefly for watchdog to start
sleep 1

# Verify watchdog started
if [ -f "$WATCHDOG_PID_FILE" ]; then
    NEW_PID=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
    if [ -n "$NEW_PID" ] && kill -0 "$NEW_PID" 2>/dev/null; then
        echo "USB Volume Fix v2 watchdog started (PID: $NEW_PID)"
    else
        echo "USB Volume Fix v2: watchdog failed to start"
    fi
else
    echo "USB Volume Fix v2: watchdog started (no PID file)"
fi

exit 0