#!/system/bin/sh
# usbvol_fix_v2_daemon.sh - USB Volume Fix v2 Daemon
#
# 修复: USB DAC 音量不响应音量键
# 原因: ColorOS AHAL 未将音量变化路由到 USB DAC
# 方法: 轮询 APM 音量 → gamma 曲线校正(预计算表) → 直接设置 USB DAC mixer 控制
# 范围: 仅影响 USB 耳机 DAC 控制，只读 cmd audio get-stream-volume（不 set、不改任何系统设置）
#
# 重要: Android /system/bin/sh 无 awk 命令!
#       使用预计算的 gamma 查找表代替浮点运算
#       gamma=0.3 (可调整: 越小越提升低段音量)

CONF_DIR=/data/adb/service.d/usbvol_fix_v2
LOG_FILE=$CONF_DIR/usbvol_fix_v2.log
PID_FILE=$CONF_DIR/.usbvol_fix_v2_daemon.pid
DISABLE_FILE=$CONF_DIR/.usbvol_fix_v2_disabled

# Source config if present (overrides defaults below; gamma is fixed in the table)
CONF_FILE=$CONF_DIR/usbvol_fix_v2.conf
[ -f "$CONF_FILE" ] && . "$CONF_FILE" 2>/dev/null

# Defaults
POLL_MS=${poll_ms:-200}
STREAM=${stream:-3}
STREAM_MAX=${stream_max:-160}
TINYMIX_BIN=/system/bin/tinymix
CARD_CHECK_INTERVAL=3

# USB DAC volume controls
USB_L_CTRL=${usb_l_ctrl:-3}
USB_L_MAX=${usb_l_max:-11520}
USB_R_CTRL=${usb_r_ctrl:-5}
USB_R_MAX=${usb_r_max:-8191}

# State
LAST_VOLUME=-1
USB_CARD=-1
LAST_CARD_CHECK=0

# ─── Logging ────────────────────────────────────────────────────────────────

log() {
    [ -n "$LOG_FILE" ] && echo "$(date '+%H:%M:%S') $1" >> "$LOG_FILE" 2>/dev/null
}

log_info() { log "INFO: $1"; }
log_warn() { log "WARN: $1"; }

rotate_log() {
    [ -f "$LOG_FILE" ] || return
    S=$(wc -c < "$LOG_FILE" 2>/dev/null); S=${S:-0}
    if [ "$S" -gt 1048576 ]; then
        tail -n 200 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null
        mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null
    fi
}

# ─── USB Card Detection ─────────────────────────────────────────────────────

detect_usb_card() {
    i=1
    while [ $i -le 8 ]; do
        [ -d "/proc/asound/card$i" ] && { echo "$i"; return 0; }
        i=$((i + 1))
    done
    echo "-1"
    return 1
}

# ─── Gamma Lookup Table ─────────────────────────────────────────────────────
# gamma=0.3, stream_max=160
# 每10步一个值，线性插值到任意idx
# 格式: idx:L值:R值
# 由 python 预计算生成，避免 shell 浮点运算

# Gamma=0.3 查找表 (每5步一个锚点，线性插值)
GAMMA_TABLE="0:0:0|1:1691:1215|2:2534:1802|3:3110:2212|4:3456:2457|5:3802:2703|6:4032:2867|7:4262:3031|8:4493:3194|9:4723:3358|10:5069:3604|11:5184:3686|12:5299:3768|13:5414:3850|14:5530:3932|15:5645:4014|16:5760:4096|17:5875:4177|18:5990:4259|19:6106:4341|20:6221:4423|21:6221:4423|22:6336:4505|23:6451:4587|24:6566:4669|25:6566:4669|26:6682:4751|27:6797:4833|28:6797:4833|29:6912:4915|30:7027:4997|31:7027:4997|32:7142:5078|33:7142:5078|34:7258:5160|35:7258:5160|36:7373:5242|37:7373:5242|38:7488:5324|39:7488:5324|40:7603:5406|41:7603:5406|42:7718:5488|43:7718:5488|44:7834:5570|45:7834:5570|46:7949:5652|47:7949:5652|48:8064:5734|49:8064:5734|50:8179:5816|51:8179:5816|52:8179:5816|53:8294:5898|54:8294:5898|55:8410:5979|56:8410:5979|57:8410:5979|58:8525:6061|59:8525:6061|60:8640:6143|61:8640:6143|62:8640:6143|63:8755:6225|64:8755:6225|65:8755:6225|66:8870:6307|67:8870:6307|68:8870:6307|69:8986:6389|70:8986:6389|71:8986:6389|72:9101:6471|73:9101:6471|74:9101:6471|75:9216:6553|76:9216:6553|77:9216:6553|78:9331:6635|79:9331:6635|80:9331:6635|81:9446:6717|82:9446:6717|83:9446:6717|84:9446:6717|85:9562:6799|86:9562:6799|87:9562:6799|88:9677:6880|89:9677:6880|90:9677:6880|91:9677:6880|92:9792:6962|93:9792:6962|94:9792:6962|95:9907:7044|96:9907:7044|97:9907:7044|98:9907:7044|99:10022:7126|100:10022:7126|101:10022:7126|102:10022:7126|103:10138:7208|104:10138:7208|105:10138:7208|106:10138:7208|107:10253:7290|108:10253:7290|109:10253:7290|110:10253:7290|111:10368:7372|112:10368:7372|113:10368:7372|114:10368:7372|115:10483:7454|116:10483:7454|117:10483:7454|118:10483:7454|119:10598:7536|120:10598:7536|121:10598:7536|122:10598:7536|123:10598:7536|124:10714:7618|125:10714:7618|126:10714:7618|127:10714:7618|128:10829:7700|129:10829:7700|130:10829:7700|131:10829:7700|132:10829:7700|133:10944:7781|134:10944:7781|135:10944:7781|136:10944:7781|137:10944:7781|138:11059:7863|139:11059:7863|140:11059:7863|141:11059:7863|142:11059:7863|143:11174:7945|144:11174:7945|145:11174:7945|146:11174:7945|147:11174:7945|148:11290:8027|149:11290:8027|150:11290:8027|151:11290:8027|152:11290:8027|153:11405:8109|154:11405:8109|155:11405:8109|156:11405:8109|157:11405:8109|158:11520:8191|159:11520:8191|160:11520:8191"

# ─── USB DAC Volume Control ─────────────────────────────────────────────────

set_usb_volume() {
    idx=$1
    [ "$USB_CARD" = "-1" ] && return

    # Clamp idx to valid range
    [ "$idx" -lt 0 ] && idx=0
    [ "$idx" -gt 160 ] && idx=160

    # Lookup gamma-corrected values from precomputed table
    # Table format: "idx:L:R|idx:L:R|..."
    # We look for exact match or interpolate between nearest values

    # Extract the entry for this index
    # Use echo + grep for table lookup
    ENTRY=$(echo "$GAMMA_TABLE" | tr '|' '\n' | grep "^${idx}:" | head -1)

    if [ -z "$ENTRY" ]; then
        # Should not happen - table has all 0-160 entries
        LV=0
        RV=0
    else
        # Parse L and R values from entry (format: "idx:L:R")
        LV=$(echo "$ENTRY" | cut -d: -f2)
        RV=$(echo "$ENTRY" | cut -d: -f3)
    fi

    # Set DAC controls via tinymix
    L_RESULT=$($TINYMIX_BIN -D "$USB_CARD" "$USB_L_CTRL" "$LV" 2>&1)
    R_RESULT=$($TINYMIX_BIN -D "$USB_CARD" "$USB_R_CTRL" "$RV" 2>&1)

    # Log
    log "VOL: $idx/160 -> L=$LV/$USB_L_MAX R=$RV/$USB_R_MAX (card=$USB_CARD)"
}

# ─── Signal Handling ────────────────────────────────────────────────────────

cleanup() {
    log_info "Shutting down (PID $$)"
    rm -f "$PID_FILE" 2>/dev/null
    exit 0
}

trap cleanup TERM INT

# ─── Main ───────────────────────────────────────────────────────────────────

main() {
    echo $$ > "$PID_FILE" 2>/dev/null
    log_info "v2 starting (PID $$)"
    log_info "Stream=$STREAM Max=$STREAM_MAX"
    log_info "USB: L=#${USB_L_CTRL}(${USB_L_MAX}) R=#${USB_R_CTRL}(${USB_R_MAX})"
    log_info "Tinymix: $TINYMIX_BIN ($(command -v $TINYMIX_BIN 2>/dev/null || echo 'NOT FOUND'))"
    log_info "Mode: USB DAC ONLY (read stream vol via cmd audio get; set USB via tinymix)"

    # Check awk is NOT available (this is critical)
    if command -v awk >/dev/null 2>&1; then
        log_info "WARNING: awk found, but using lookup table anyway"
    else
        log_info "Confirmed: no awk (using precomputed table)"
    fi

    [ -f "$DISABLE_FILE" ] && { log_warn "Disabled via $DISABLE_FILE"; exit 0; }

    # Verify lookup table works with a test
    TEST_ENTRY=$(echo "$GAMMA_TABLE" | tr '|' '\n' | grep "^80:" | head -1)
    TEST_L=$(echo "$TEST_ENTRY" | cut -d: -f2)
    TEST_R=$(echo "$TEST_ENTRY" | cut -d: -f3)
    log_info "Table test: idx=80 -> L=$TEST_L R=$TEST_R"

    while true; do
        [ -f "$DISABLE_FILE" ] && { log_warn "Disabled, exiting"; exit 0; }
        rotate_log

        # Check USB card EVERY iteration (cheap: just stat a directory)
        # This ensures we stop calling cmd audio immediately when USB disconnects
        NEW=$(detect_usb_card)
        if [ "$NEW" != "$USB_CARD" ]; then
            log_info "USB: $USB_CARD -> $NEW"
            USB_CARD=$NEW
            LAST_VOLUME=-1
            # On disconnect: exit immediately. Watchdog restarts on reconnect.
            # Do NOT restart audio HAL / change system settings (caused speaker regression).
            if [ "$USB_CARD" = "-1" ]; then
                log_info "USB disconnected, exiting (watchdog manages reconnect)"
                rm -f "$PID_FILE" 2>/dev/null
                exit 0
            fi
        fi

        # If no USB earphone, sleep and continue - do NOT poll cmd audio
        if [ "$USB_CARD" = "-1" ]; then
            sleep 1
            continue
        fi

        # USB earphone connected - poll APM volume
        CUR=$(cmd audio get-stream-volume "$STREAM" 2>/dev/null | sed -n 's/.*-> //p' | tail -n1)
        CUR=${CUR:-0}

        # Only sync if volume changed
        if [ "$CUR" != "$LAST_VOLUME" ]; then
            log_info "Vol: $LAST_VOLUME -> $CUR"
            set_usb_volume "$CUR"
            LAST_VOLUME="$CUR"
        fi

        sleep 0.2
    done
}

main "$@"
