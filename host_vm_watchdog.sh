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
#    - Neu fail: ping VM qua Host-only IP (timeout 30s)
#        - Neu Host-only cung fail: gui webhook CRITICAL, exit
#        - Neu Host-only OK: kiem tra task ssh_keepalive_vm qua Get-ScheduledTaskInfo
#            - Neu task khong o trang thai Running: chay lai qua schtasks, gui webhook
#            - Neu dang Running: gui webhook thong bao van dang cho keepalive tu phuc hoi

export LC_ALL=C
export TZ='Asia/Tokyo'
WIN_USERNAME="$USERNAME"
export HOME="/c/Users/$WIN_USERNAME"
export MSYSTEM=MINGW64
export PATH="/usr/bin:/mingw64/bin:/c/Windows/System32:$PATH"

WG_PEER_IP="10.9.0.1"
VM_WG_IP="10.9.0.107"
VM_HOSTONLY_IP="192.168.56.99"
VM_HOSTONLY_TIMEOUT=30
WG_ADAPTER_NAME="srjp"
KEEPALIVE_TASK_NAME="ssh_keepalive_vm"
LOGFILE="/c/Users/$WIN_USERNAME/Documents/log/host-vm-watchdog.log"
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

# Ping voi timeout tuy chinh (dung -w cho moi packet, tinh bang ms), Windows ping
ping_check_timeout() {
    local ip="$1"
    local timeout_sec="$2"
    local timeout_ms=$((timeout_sec * 1000))
    ping -n 3 -w "$timeout_ms" "$ip" > /dev/null 2>&1
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

# Buoc 2: Peer da OK, tiep tuc ping VM qua WireGuard IP
echo "$(timestamp) - Kiem tra VM qua WireGuard IP $VM_WG_IP..." >> "$LOGFILE"

if ping_check "$VM_WG_IP"; then
    echo "$(timestamp) - Ping OK to VM $VM_WG_IP" >> "$LOGFILE"
    exit 0
fi

echo "$(timestamp) - Ping FAIL to VM $VM_WG_IP, kiem tra qua Host-only IP $VM_HOSTONLY_IP (timeout ${VM_HOSTONLY_TIMEOUT}s)..." >> "$LOGFILE"

# Buoc 3: WireGuard IP fail, thu ping Host-only IP voi timeout dai hon
if ! ping_check_timeout "$VM_HOSTONLY_IP" "$VM_HOSTONLY_TIMEOUT"; then
    echo "$(timestamp) - Host-only IP $VM_HOSTONLY_IP cung FAIL sau ${VM_HOSTONLY_TIMEOUT}s. VM co the down hoan toan." >> "$LOGFILE"
    send_webhook "CRITICAL: VM khong phan hoi ca WireGuard ($VM_WG_IP) lan Host-only ($VM_HOSTONLY_IP) - can kiem tra thu cong ngay"
    exit 1
fi

echo "$(timestamp) - Host-only IP OK. Kiem tra task $KEEPALIVE_TASK_NAME qua Get-ScheduledTaskInfo..." >> "$LOGFILE"

# Buoc 4: Host-only OK, kiem tra trang thai task ssh_keepalive_vm
TASK_STATE=$(powershell.exe -NoProfile -Command "(Get-ScheduledTask -TaskName '$KEEPALIVE_TASK_NAME').State" 2>>"$LOGFILE" | tr -d '\r')

echo "$(timestamp) - Task $KEEPALIVE_TASK_NAME State: $TASK_STATE" >> "$LOGFILE"

if [ "$TASK_STATE" = "Running" ]; then
    echo "$(timestamp) - Task dang Running, nhung VM van khong ping duoc qua WireGuard" >> "$LOGFILE"
    send_webhook "WARNING: VM $VM_WG_IP FAIL ping qua WireGuard nhung Host-only OK, task $KEEPALIVE_TASK_NAME dang Running - co the can them thoi gian de tu phuc hoi"
else
    echo "$(timestamp) - Task KHONG o trang thai Running (state: $TASK_STATE), khoi dong lai..." >> "$LOGFILE"
    schtasks /run /tn "$KEEPALIVE_TASK_NAME" >> "$LOGFILE" 2>&1
    send_webhook "WARNING: VM $VM_WG_IP FAIL ping qua WireGuard, task $KEEPALIVE_TASK_NAME khong Running (state: $TASK_STATE) - vua duoc khoi dong lai tu dong"
fi

exit 0
