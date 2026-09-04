#!/bin/bash
# host-wg-vm-watchdog.sh
#
# Logic:
# 1. Ping WireGuard peer (host-side). Neu fail:
#    - Restart WireGuard adapter tren host (1 lan)
#    - Doi 5s, ping lai peer
#    - Neu van fail: gui webhook, exit
# 2. Neu ping peer OK: tiep tuc ping VM qua WireGuard IP
#    - Neu OK: exit 0
#    - Neu fail: SSH vao VM (1 lan, co timeout), gui webhook ket qua SSH (thanh cong/fail/timeout), exit

export LC_ALL=C
export TZ='Asia/Tokyo'
export HOME="/c/Users/SR_admin"
export MSYSTEM=MINGW64
export PATH="/usr/bin:/mingw64/bin:/c/Windows/System32:$PATH"

WG_PEER_IP="10.9.0.1"
VM_WG_IP="10.9.0.107"
WG_ADAPTER_NAME="srjp"
SSH_HOST="this-deb"
SSH_TIMEOUT=15
LOGFILE="/c/Users/SR_admin/Documents/log/host-vm-watchdog.log"
WEBHOOK_URL="https://b1n0-vn.giize.com/general-webhook"
WEBHOOK_SECRET="KhdvIf0Db/yk8qmNR3EgKksNRurj6O/2KWyXC90yLQc="

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

mkdir -p "$(dirname "$LOGFILE")"

send_webhook() {
    local msg="$1"
    local ts
    ts=$(timestamp)
    local payload
    payload=$(printf '{"text":"%s","timestamp":"%s"}' "$msg" "$ts")
    local signature
    signature=$(printf '%s' "$payload" | /mingw64/bin/openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" -hex 2>>"$LOGFILE" | awk '{print $2}')
    curl -s -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -H "X-Signature-256: sha256=${signature}" \
        -d "$payload" >> "$LOGFILE" 2>&1
}

ping_check() {
    local ip="$1"
    ping -n 3 "$ip" > /dev/null 2>&1
    return $?
}

echo "$(timestamp) - Bat dau kiem tra WireGuard peer $WG_PEER_IP" >> "$LOGFILE"

# Buoc 1: Ping peer
if ! ping_check "$WG_PEER_IP"; then
    echo "$(timestamp) - Ping FAIL to peer $WG_PEER_IP, restart WireGuard interface tren host..." >> "$LOGFILE"

    powershell.exe -Command "Disable-NetAdapter -Name '$WG_ADAPTER_NAME' -Confirm:\$false" >> "$LOGFILE" 2>&1
    sleep 3
    powershell.exe -Command "Enable-NetAdapter -Name '$WG_ADAPTER_NAME' -Confirm:\$false" >> "$LOGFILE" 2>&1
    sleep 5

    echo "$(timestamp) - Da restart interface, ping lai peer..." >> "$LOGFILE"

    if ! ping_check "$WG_PEER_IP"; then
        echo "$(timestamp) - Peer van FAIL sau restart interface. Dung script." >> "$LOGFILE"
        send_webhook "CRITICAL: Khong the ket noi WireGuard peer $WG_PEER_IP tu host sau khi restart interface"
        exit 1
    fi

    echo "$(timestamp) - Peer OK sau restart interface" >> "$LOGFILE"
else
    echo "$(timestamp) - Ping OK to peer $WG_PEER_IP" >> "$LOGFILE"
fi

# Buoc 2: Peer da OK, tiep tuc ping VM
echo "$(timestamp) - Kiem tra VM qua WireGuard IP $VM_WG_IP..." >> "$LOGFILE"

if ping_check "$VM_WG_IP"; then
    echo "$(timestamp) - Ping OK to VM $VM_WG_IP" >> "$LOGFILE"
    exit 0
fi

echo "$(timestamp) - Ping FAIL to VM $VM_WG_IP, thu SSH vao $SSH_HOST (timeout ${SSH_TIMEOUT}s)..." >> "$LOGFILE"

timeout "$SSH_TIMEOUT" ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_HOST" \
    "uptime; echo 'SSH triggered at' \$(date)" >> "$LOGFILE" 2>&1
SSH_RESULT=$?

if [ $SSH_RESULT -eq 0 ]; then
    echo "$(timestamp) - SSH thanh cong" >> "$LOGFILE"
    send_webhook "WARNING: VM $VM_WG_IP FAIL ping, da thu SSH va thanh cong"
elif [ $SSH_RESULT -eq 124 ]; then
    echo "$(timestamp) - SSH TIMEOUT sau ${SSH_TIMEOUT}s, VM co the dang treo hoac khong phan hoi" >> "$LOGFILE"
    send_webhook "CRITICAL: VM $VM_WG_IP FAIL ping, SSH TIMEOUT sau ${SSH_TIMEOUT}s - VM co the dang treo, can kiem tra thu cong ngay"
else
    echo "$(timestamp) - SSH FAIL (exit code $SSH_RESULT)" >> "$LOGFILE"
    send_webhook "CRITICAL: VM $VM_WG_IP FAIL ping, SSH THAT BAI (exit code $SSH_RESULT) - can kiem tra thu cong"
fi

exit 0
