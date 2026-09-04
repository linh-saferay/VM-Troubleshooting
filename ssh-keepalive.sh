#!/bin/bash
# ssh-keepalive.sh
export PATH="/usr/bin:/mingw64/bin:$PATH"
LOGFILE="/c/Users/SR_admin/Documents/log/ssh-keepalive.log"
mkdir -p "$(dirname "$LOGFILE")"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

while true; do
    echo "$(timestamp) - Starting SSH keepalive session..." >> "$LOGFILE"
    ssh -N \
        -o "ServerAliveInterval 30" \
        -o "ServerAliveCountMax 3" \
        -o "BatchMode=yes" \
        -o "StrictHostKeyChecking=no" \
        this-deb-hostonly >> "$LOGFILE" 2>&1
    echo "$(timestamp) - SSH session ended, reconnecting in 5s..." >> "$LOGFILE"
    sleep 5
done
