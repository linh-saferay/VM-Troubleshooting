# VM Watchdog & SSH Keepalive - Manual

Scripts to keep a VirtualBox VM (Debian, WireGuard client) reachable from a Windows host, and auto-recover when the connection drops.

## Overview

Three components work together:

| File | Purpose | Trigger |
|---|---|---|
| `ssh-keepalive.sh` | Holds a persistent SSH session to the VM (via Host-only network). Auto-reconnects if dropped. | Task Scheduler, "At startup" |
| `host_vm_watchdog.sh` | Periodically checks WireGuard + VM reachability. Restarts WireGuard adapter or the keepalive task when needed. Sends webhook alerts. | Task Scheduler, every 30 min |
| `create-watchdog-tasks.ps1` | One-shot PowerShell script to register both scripts as Scheduled Tasks. | Run manually once per host |

## Why this exists

VirtualBox Bridged networking on Windows (Realtek NIC) periodically resets the network interface (`Event ID 10400`), silently dropping the VM's WireGuard tunnel. SSH into the VM was observed to "wake up" the connection. Instead of manually SSH-ing in every time, `ssh-keepalive.sh` keeps a session alive permanently, and `host_vm_watchdog.sh` watches for failures and restarts things automatically.

## Prerequisites (per host)

- Git Bash installed at `C:\Program Files\Git\usr\bin\bash.exe`
- SSH key-based auth already set up (`~/.ssh/config` with a Host-only alias, e.g. `this-deb-hostonly`)
- User account has "Log on as a batch job" right (check via `secpol.msc` -> Local Policies -> User Rights Assignment)
- `openssl` available at `/mingw64/bin/openssl` (comes with Git Bash)

## Setup

1. Copy `host_vm_watchdog.sh` and `ssh-keepalive.sh` to `C:\Users\<username>\scritps\`
2. Edit the variables at the top of `host_vm_watchdog.sh`:
   - `WG_PEER_IP` - WireGuard peer IP on the host side
   - `VM_WG_IP` - VM's WireGuard IP
   - `VM_HOSTONLY_IP` - VM's Host-only network IP
   - `WG_ADAPTER_NAME` - WireGuard adapter name as shown in Windows (`Get-NetAdapter`)
   - `WEBHOOK_URL` / `WEBHOOK_SECRET` - for HMAC-signed webhook notifications
3. Edit `ssh-keepalive.sh`:
   - Replace `this-deb-hostonly` with your actual SSH host alias
4. Run `create-watchdog-tasks.ps1` as Administrator (or as the target user) to register both Scheduled Tasks. It will prompt for the account password twice.

## host_vm_watchdog.sh logic

```
1. Ping WireGuard peer (host side)
   - Fail -> restart WireGuard adapter (Disable/Enable-NetAdapter), wait 5s, ping again
     - Still fail -> webhook CRITICAL, exit
2. Peer OK -> ping VM via WireGuard IP
   - OK -> exit 0 (nothing to do)
   - Fail -> ping VM via Host-only IP (30s timeout)
     - Also fail -> webhook CRITICAL (VM likely fully down), exit
     - OK -> check ssh_keepalive_vm task state via Get-ScheduledTask
       - State != Running -> schtasks /run to restart it, webhook WARNING
       - State == Running -> webhook WARNING (give it more time to self-recover)
```

## ssh-keepalive.sh logic

Infinite loop: opens a no-command SSH session (`-N`) with `ServerAliveInterval 30`, logs start/end events, waits 5s and reconnects if the session drops for any reason (network blip, host sleep, etc).

## Common operations

**Check task status:**
```powershell
Get-ScheduledTaskInfo -TaskName "host_vm_watchdog"
Get-ScheduledTaskInfo -TaskName "ssh_keepalive_vm"
```

**Manually trigger a run:**
```powershell
schtasks /run /tn "host_vm_watchdog"
schtasks /run /tn "ssh_keepalive_vm"
```

**Change watchdog interval (minutes):**
```powershell
schtasks /change /tn "host_vm_watchdog" /ri 30
```

**Disable / re-enable a task:**
```powershell
schtasks /change /tn "host_vm_watchdog" /disable
schtasks /change /tn "host_vm_watchdog" /enable
```

**View logs:**
```bash
tail -30 /c/Users/<username>/Documents/log/host-vm-watchdog.log
tail -30 /c/Users/<username>/Documents/log/ssh-keepalive.log
```

## Task Scheduler result codes seen in practice

| Code | Meaning | Notes |
|---|---|---|
| `0` | Success | Normal completion |
| `267009` (`0x41301`) | Task currently running | Normal for `ssh_keepalive_vm` (infinite loop, never exits) |
| `267014` (`0x41406`) | Task terminated | Usually caused by host sleep/hibernate killing the process. Check `Get-WinEvent -LogName System` for Event ID 1 (wake) / 42 (sleep) around that time. Just re-run the task. |
| `127` | Command not found | Wrong path to `bash.exe` or the `.sh` script, or wrong username in path. Verify with `Test-Path`. |
| `2147946720` (`0x800710E0`) | Operator/admin refused the request | Credential issue. Delete and recreate the task with `/rp *` to re-enter the password, or check "Log on as a batch job" right. |

## Known gotchas

- **`schtasks /create /tr` with paths containing spaces** (e.g. `C:\Program Files\...`) needs the whole `Execute` value quoted, e.g. `"'C:\Program Files\Git\usr\bin\bash.exe' -c '...'"`. Wrong quoting causes exit code `127`.
- **`Set-ScheduledTask` may ask for credentials again** even if the task already has them stored — this is normal for tasks running under a specific user (not SYSTEM). Prefer editing via Task Scheduler GUI if it fails, or recreate via `schtasks /create ... /rp *`.
- **VM must NOT be sitting at a GUI login screen** (e.g. XFCE + LightDM) unattended — SSH can hang indefinitely waiting on a display-manager-related session lock. Run headless VMs with `systemctl set-default multi-user.target` instead of `graphical.target`.
- **`ConnectTimeout` in `ssh` is not always honored** if the tunnel is a "black hole" (no ICMP/TCP RST). Always wrap SSH calls in `timeout <seconds> ssh ...` as a hard safety net.
- **HMAC signature payload must match exactly** between bash (`printf`) and the receiving server's `JSON.stringify()` — no extra whitespace. Keep the JSON compact (`{"key":"value"}`, no spaces after `:`/`,`).

## File/script content language rule

All comments, debug lines, and sample data inside scripts must be in English or Vietnamese without diacritics (no dấu), to avoid encoding/hash mismatches. Chat-facing documentation (like this file) can use normal formatting.