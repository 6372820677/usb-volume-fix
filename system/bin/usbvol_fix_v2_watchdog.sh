#!/system/bin/sh
# USB Volume Fix v2 - Watchdog (minimal version)
# Only runs when USB DAC is connected, kills daemon when USB disconnects
# Uses inotify-like polling but with minimal overhead

LOG=/data/adb/service.d/usbvol_fix_v2/usbvol_fix_v2.log
DAEMON_PATH=/data/adb/modules/usb_volume_fix_v2/system/bin/usbvol_fix_v2_daemon.sh
DAEMON_PID_FILE=/data/adb/service.d/usbvol_fix_v2/.usbvol_fix_v2_daemon.pid
WATCHDOG_PID_FILE=/data/adb/service.d/usbvol_fix_v2/.usbvol_fix_v2_watchdog.pid

# Detect USB card by checking /proc/asound
detect_usb_card() {
    for i in 1 2 3 4 5 6 7 8; do
        if [ -d "/proc/asound/card$i" ]; then
            echo "$i"
            return
        fi
    done
    echo "-1"
}

log() {
    echo "$(date +%H:%M:%S) WATCH: $1" >> $LOG 2>/dev/null
}

# Start volume daemon
start_daemon() {
    if [ -f "$DAEMON_PID_FILE" ]; then
        PID=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            log "Daemon already running (PID $PID)"
            return
        fi
    fi
    log "Starting daemon..."
    setsid "$DAEMON_PATH" </dev/null >/dev/null 2>&1 &
    sleep 1
    if [ -f "$DAEMON_PID_FILE" ]; then
        log "Daemon started (PID $(cat $DAEMON_PID_FILE))"
    else
        log "ERROR: Failed to start daemon"
    fi
}

# Kill volume daemon
kill_daemon() {
    if [ -f "$DAEMON_PID_FILE" ]; then
        PID=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            log "Killing daemon (PID $PID)"
            kill "$PID" 2>/dev/null
            sleep 1
            if kill -0 "$PID" 2>/dev/null; then
                kill -9 "$PID" 2>/dev/null
            fi
            rm -f "$DAEMON_PID_FILE"
            log "Daemon killed"
        fi
    fi
    pkill -f "$DAEMON_PATH" 2>/dev/null
}

# Main loop
echo $$ > "$WATCHDOG_PID_FILE"
log "Watchdog started (PID $$)"

USB_CARD="-1"
while true; do
    NEW_CARD=$(detect_usb_card)
    
    if [ "$NEW_CARD" != "$USB_CARD" ]; then
        if [ "$NEW_CARD" = "-1" ]; then
            # USB disconnected
            log "USB disconnected"
            kill_daemon
        else
            # USB connected
            log "USB connected (card $NEW_CARD)"
            start_daemon
        fi
        USB_CARD=$NEW_CARD
    fi
    
    sleep 1
done