#!/usr/bin/env bash
# troubleshoot_suspend.sh
# Diagnose unexpected suspend / power issues on Linux desktop-with-GDM hosts.
# Read-only checks only - safe to run anytime, does not change system state.
# Usage: bash troubleshoot_suspend.sh [--since "YYYY-MM-DD HH:MM"] [--until "YYYY-MM-DD HH:MM"]

SINCE=""
UNTIL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --until) UNTIL="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done
[[ -z "$SINCE" ]] && SINCE=$(date -d "-2 hours" "+%Y-%m-%d %H:%M")
[[ -z "$UNTIL" ]] && UNTIL=$(date "+%Y-%m-%d %H:%M")

hr() { printf '\n=== %s ===\n' "$1"; }

hr "1. Basic uptime / boot info"
uptime
echo "---"
who -b 2>/dev/null
last -x -n 10

hr "2. Current power state (kernel level, bypasses upowerd)"
for bat in /sys/class/power_supply/BAT*; do
  [[ -d "$bat" ]] || continue
  echo "-- $bat --"
  echo "status:     $(cat "$bat/status" 2>/dev/null)"
  echo "capacity:   $(cat "$bat/capacity" 2>/dev/null)%"
  echo "energy_now: $(cat "$bat/energy_now" 2>/dev/null || cat "$bat/charge_now" 2>/dev/null)"
  echo "power_now:  $(cat "$bat/power_now" 2>/dev/null)"
done
for ac in /sys/class/power_supply/A{C,DP}*; do
  [[ -d "$ac" ]] || continue
  echo "-- $ac --"
  echo "online: $(cat "$ac/online" 2>/dev/null)"
done

hr "3. Current power state (upower daemon view - compare against section 2)"
upower -i "$(upower -e | grep -i line_power)" 2>/dev/null | grep -i online
upower -i "$(upower -e | grep -i bat)" 2>/dev/null | grep -Ei "state|percentage|time to (full|empty)"

hr "4. Who/what requested suspend recently"
journalctl --since "$SINCE" --until "$UNTIL" \
  | grep -Ei "suspend|sleep|hibernate|lid|PM: suspend|logind.*power key" \
  | grep -v "monitoring_sftp\|Removed session [0-9]"

hr "5. suspend/hibernate target status (masked = blocked)"
systemctl status sleep.target suspend.target hibernate.target hybrid-sleep.target --no-pager 2>&1 | grep -E "^\S|Loaded:|Active:"

hr "6. GDM greeter power settings (idle-suspend on login screen)"
if id gdm &>/dev/null; then
  echo "AC:      $(sudo -u gdm env DCONF_PROFILE=gdm dbus-run-session gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 2>/dev/null)"
  echo "Battery: $(sudo -u gdm env DCONF_PROFILE=gdm dbus-run-session gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 2>/dev/null)"
else
  echo "no gdm user on this host - skip"
fi

hr "7. Logged-in sessions (identify which are real GUI vs SSH vs login screen)"
loginctl list-sessions
echo "---"
loginctl list-sessions --no-legend | awk '{print $1}' | while read -r s; do
  echo "-- session $s --"
  loginctl show-session "$s" -p Name -p Type -p Class -p State -p IdleHint -p IdleSinceHint 2>/dev/null
done

hr "8. Noise-filtered raw log around the window (for eyeballing lid/key/power events)"
journalctl --since "$SINCE" --until "$UNTIL" \
  | grep -vE "monitoring_sftp|Removed session|session-[0-9]+\.scope|user@|Dynu|snapd-desktop|xdg-document-portal"

hr "9. Any crash / OOM around the window"
journalctl --since "$SINCE" --until "$UNTIL" \
  | grep -Ei "segfault|core.?dump|oom|killed process|out of memory"

hr "10. Suspend/resume pairs since last boot(s)"
journalctl -b 0  -g "PM: suspend (entry|exit)" -o short-iso 2>/dev/null
journalctl -b -1 -g "PM: suspend (entry|exit)" -o short-iso 2>/dev/null

echo
echo "Done. Key things to look at:"
echo "  - Section 2 vs 3 mismatch  -> upowerd stale, restart: sudo systemctl restart upower"
echo "  - Section 2 online=0       -> running on battery, check AC/charger at site"
echo "  - Section 5 shows masked   -> suspend blocked; low-battery safety suspend also blocked"
echo "  - Section 6 not 'nothing'  -> login screen will auto-suspend on idle"
echo "  - Section 7 session on seat0/ttyN owned by gdm, idle=yes -> that's the login screen, not a real user"
