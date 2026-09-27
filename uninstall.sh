#!/system/bin/sh
# uninstall.sh - Clean up USB Volume Fix v2

CONF_DIR=/data/adb/service.d/usbvol_fix_v2
DAEMON_PID_FILE=$CONF_DIR/.usbvol_fix_v2_daemon.pid
WATCHDOG_PID_FILE=$CONF_DIR/.usbvol_fix_v2_watchdog.pid

# Kill a process by PID file (TERM then KILL)
kill_pidfile() {
    PF=$1
    [ -f "$PF" ] || return
    PID=$(cat "$PF" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
        sleep 0.5
        kill -9 "$PID" 2>/dev/null
    fi
    rm -f "$PF" 2>/dev/null
}

# Kill watchdog FIRST (so it does not restart the daemon), then daemon
kill_pidfile "$WATCHDOG_PID_FILE"
kill_pidfile "$DAEMON_PID_FILE"

# Backup: kill lingering processes by script name.
# IMPORTANT: do NOT use pkill -f "usb_volume_fix_v2" -- that pattern matches
# this uninstall script's own path and would kill itself mid-execution.
pkill -f "usbvol_fix_v2_watchdog" 2>/dev/null
pkill -f "usbvol_fix_v2_daemon" 2>/dev/null

# Remove state files
rm -f "$CONF_DIR/usbvol_fix_v2.conf" 2>/dev/null
rm -f "$CONF_DIR/usbvol_fix_v2.log" 2>/dev/null
rm -f "$CONF_DIR/.usbvol_fix_v2_disabled" 2>/dev/null
rmdir "$CONF_DIR" 2>/dev/null

exit 0
