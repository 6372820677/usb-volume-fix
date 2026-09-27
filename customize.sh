#!/system/bin/sh
# customize.sh - Set executable permissions on daemon script

system_bin="$MODPATH/system/bin"

if [ -d "$system_bin" ]; then
    chmod 755 "$system_bin/usbvol_fix_v2_daemon.sh" 2>/dev/null
    chmod 755 "$system_bin/usbvol_fix_v2_watchdog.sh" 2>/dev/null
fi

exit 0
