#!/system/bin/sh
# post-fs-data.sh - Prepare directories and permissions for USB Volume Fix v2

CONF_DIR=/data/adb/service.d/usbvol_fix_v2
mkdir -p "$CONF_DIR" 2>/dev/null

# Set ownership
chown root:shell "$CONF_DIR" 2>/dev/null
chmod 755 "$CONF_DIR" 2>/dev/null

# Copy clean default config from module if not present (no v1 device-id leftovers)
CONF=$CONF_DIR/usbvol_fix_v2.conf
if [ ! -f "$CONF" ]; then
    cp "$MODPATH/usbvol_fix_v2.conf" "$CONF" 2>/dev/null
    chmod 644 "$CONF" 2>/dev/null
    chown root:shell "$CONF" 2>/dev/null
fi

exit 0
