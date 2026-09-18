#!/bin/bash
# wg-handshake-check.sh
# For linux host that has LAN Gateway also connected to same wireguard (leading ping success even host not connected to wireguard at all)
# Check WireGuard handshake status, restart interface if handshake missing or too old

WG_INTERFACE="srjp"           # doi dung ten interface
HANDSHAKE_THRESHOLD_SEC=150   # WireGuard rekey moi 120s, qua nguong nay la dau hieu dead
LOGFILE="/var/log/wg-handshake-check.log"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

# Extract handshake age in seconds from `wg show` text output
# Returns -1 if no handshake line found (peer never connected)
get_handshake_age_sec() {
    local wg_output="$1"
    local line
    line=$(echo "$wg_output" | grep "latest handshake:")

    if [ -z "$line" ]; then
        echo "-1"
        return
    fi

    local text
    text=$(echo "$line" | sed 's/.*latest handshake: //')

    if [ "$text" = "Now" ]; then
        echo 0
        return
    fi

    local days=0 hours=0 minutes=0 seconds=0
    [[ "$text" =~ ([0-9]+)\ day ]] && days=${BASH_REMATCH[1]}
    [[ "$text" =~ ([0-9]+)\ hour ]] && hours=${BASH_REMATCH[1]}
    [[ "$text" =~ ([0-9]+)\ minute ]] && minutes=${BASH_REMATCH[1]}
    [[ "$text" =~ ([0-9]+)\ second ]] && seconds=${BASH_REMATCH[1]}

    echo $(( days*86400 + hours*3600 + minutes*60 + seconds ))
}

WG_OUTPUT=$( wg show "$WG_INTERFACE" 2>>"$LOGFILE")

if [ -z "$WG_OUTPUT" ]; then
    echo "$(timestamp) - Khong lay duoc wg show output, interface co the khong ton tai, start new now" >> "$LOGFILE"
    wg-quick up "$WG_INTERFACE" >> "$LOGFILE" 2>&1
    echo "$(timestamp) - Da start xong" >> "$LOGFILE"
    exit 0
fi

HANDSHAKE_AGE=$(get_handshake_age_sec "$WG_OUTPUT")

if [ "$HANDSHAKE_AGE" -eq -1 ]; then
    echo "$(timestamp) - Chua co handshake nao (peer chua ket noi lan nao)" >> "$LOGFILE"
    NEED_RESTART=1
elif [ "$HANDSHAKE_AGE" -gt "$HANDSHAKE_THRESHOLD_SEC" ]; then
    echo "$(timestamp) - Handshake qua cu (${HANDSHAKE_AGE}s > ${HANDSHAKE_THRESHOLD_SEC}s)" >> "$LOGFILE"
    NEED_RESTART=1
else
    echo "$(timestamp) - Handshake OK (${HANDSHAKE_AGE}s)" >> "$LOGFILE"
    NEED_RESTART=0
fi

if [ "$NEED_RESTART" -eq 1 ]; then
    echo "$(timestamp) - Restarting WireGuard interface $WG_INTERFACE..." >> "$LOGFILE"
     wg-quick down "$WG_INTERFACE" >> "$LOGFILE" 2>&1
    sleep 2
     wg-quick up "$WG_INTERFACE" >> "$LOGFILE" 2>&1
    echo "$(timestamp) - Da restart xong" >> "$LOGFILE"
fi
