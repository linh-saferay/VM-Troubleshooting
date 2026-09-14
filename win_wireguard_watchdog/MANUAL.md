# WireGuard Tunnel Manager (Windows 11 / PowerShell)

Scripts to manually control, auto-monitor, and log-maintain a WireGuard tunnel
installed as a Windows service on Windows 11.

## Contents

| File | Purpose |
|---|---|
| `Manage-WireGuardTunnel.ps1` | Manually start / stop / restart / check status of the tunnel |
| `Monitor-WireGuardTunnel.ps1` | Pings a target IP; restarts the tunnel service if unreachable |
| `Setup-WireGuardMonitorTask.ps1` | Registers a scheduled task that runs the monitor periodically |
| `Prune-WireGuardLog.ps1` | Removes log entries older than N days |
| `Setup-WireGuardLogCleanupTask.ps1` | Registers a scheduled task that runs the pruner daily |

## Prerequisites

- Windows 11
- WireGuard tunnel already imported and activated via the WireGuard GUI, so it
  runs as a Windows service named `WireGuardTunnel$<TunnelName>`
- PowerShell run **as Administrator** for any setup or service-control command
- All `.ps1` files placed in the same folder, e.g. `C:\WireGuardMonitor\`

Check your tunnel's service name:

```powershell
Get-Service -Name "WireGuardTunnel*" | Select-Object Name, Status
```

---

## 1. Manage-WireGuardTunnel.ps1

Manually start, stop, restart, or check the tunnel service.

```powershell
.\Manage-WireGuardTunnel.ps1 -Action Start   -TunnelName srjp
.\Manage-WireGuardTunnel.ps1 -Action Stop    -TunnelName srjp
.\Manage-WireGuardTunnel.ps1 -Action Restart -TunnelName srjp
.\Manage-WireGuardTunnel.ps1 -Action Status  -TunnelName srjp
```

`-TunnelName` defaults to `srjp` if omitted. Must run elevated.

---

## 2. Monitor-WireGuardTunnel.ps1

Pings `-TargetIP` through the tunnel. If all pings fail, restarts the tunnel
service and logs the outcome.

```powershell
.\Monitor-WireGuardTunnel.ps1 -TunnelName srjp -TargetIP 10.9.0.1
```

| Parameter | Default | Description |
|---|---|---|
| `-TunnelName` | `srjp` | Tunnel to restart on failure |
| `-TargetIP` | `10.9.0.1` | Address to ping |
| `-PingCount` | `4` | Pings sent before declaring failure |
| `-LogPath` | `C:\WireGuardMonitor\wireguard-monitor.log` | Log file (auto-created) |

Can be run manually to test, but is normally invoked automatically by the
scheduled task below.

---

## 3. Setup-WireGuardMonitorTask.ps1

Registers a Task Scheduler task (runs as `SYSTEM`, works with no user logged
in) that calls `Monitor-WireGuardTunnel.ps1` on a repeating interval,
indefinitely.

```powershell
.\Setup-WireGuardMonitorTask.ps1 -TunnelName srjp -TargetIP 10.9.0.1 -IntervalMinutes 10
```

| Parameter | Default | Description |
|---|---|---|
| `-ScriptPath` | same folder as this script | Path to `Monitor-WireGuardTunnel.ps1` |
| `-TunnelName` | `srjp` | Passed through to the monitor script |
| `-TargetIP` | `10.9.0.1` | Passed through to the monitor script |
| `-IntervalMinutes` | `5` | How often the task fires |
| `-TaskName` | `WireGuard Tunnel Monitor` | Scheduled task name |

Re-running this script safely replaces an existing task of the same name
(e.g. to change the interval).

**Note:** the trigger deliberately omits `-RepetitionDuration`. Passing
`[TimeSpan]::MaxValue` serializes to an out-of-range Task Scheduler XML
duration (`P99999999DT23H59M59S`) and `Register-ScheduledTask` rejects it.
Omitting the parameter makes the repetition indefinite by default.

---

## 4. Prune-WireGuardLog.ps1

Keeps only the last `-RetentionDays` days of entries in the log file; older
lines are dropped. Lines that don't match the expected timestamp format are
kept as-is (fail-safe).

```powershell
.\Prune-WireGuardLog.ps1 -LogPath "C:\WireGuardMonitor\wireguard-monitor.log" -RetentionDays 30
```

---

## 5. Setup-WireGuardLogCleanupTask.ps1

Registers a daily scheduled task (runs as `SYSTEM`) that calls
`Prune-WireGuardLog.ps1`, keeping a rolling window of log history instead of
letting the file grow forever.

```powershell
.\Setup-WireGuardLogCleanupTask.ps1 -RetentionDays 30 -At "00:30"
```

| Parameter | Default | Description |
|---|---|---|
| `-ScriptPath` | same folder as this script | Path to `Prune-WireGuardLog.ps1` |
| `-LogPath` | `C:\WireGuardMonitor\wireguard-monitor.log` | Log file to prune |
| `-RetentionDays` | `30` | Days of history to keep |
| `-At` | `00:30` | Time of day the task runs |
| `-TaskName` | `WireGuard Log Cleanup` | Scheduled task name |

---

## First-time setup (full walkthrough)

```powershell
# 1. Create a folder for the scripts
New-Item -ItemType Directory -Path "C:\WireGuardMonitor" -Force

# 2. Copy all .ps1 files into C:\WireGuardMonitor\

# 3. Open PowerShell as Administrator, then:
cd C:\WireGuardMonitor

# 4. Register the tunnel monitor (auto-restart on ping failure)
.\Setup-WireGuardMonitorTask.ps1 -TunnelName srjp -TargetIP 10.9.0.1 -IntervalMinutes 10

# 5. Register the daily log pruner (keep last 30 days)
.\Setup-WireGuardLogCleanupTask.ps1 -RetentionDays 30 -At "00:30"
```

The log file (`wireguard-monitor.log`) is created automatically on first
write — no need to create it manually.

---

## Verifying tasks

```powershell
Get-ScheduledTask -TaskName "WireGuard Tunnel Monitor" | Get-ScheduledTaskInfo
Get-ScheduledTask -TaskName "WireGuard Log Cleanup"    | Get-ScheduledTaskInfo

# Check the monitor's repeat interval
Get-ScheduledTask -TaskName "WireGuard Tunnel Monitor" | Select-Object -ExpandProperty Triggers

# Tail the log
Get-Content "C:\WireGuardMonitor\wireguard-monitor.log" -Tail 20
```

## Removing tasks

```powershell
Unregister-ScheduledTask -TaskName "WireGuard Tunnel Monitor" -Confirm:$false
Unregister-ScheduledTask -TaskName "WireGuard Log Cleanup" -Confirm:$false
```

## Troubleshooting

- **`Register-ScheduledTask` fails with an XML duration error** — see the
  note under section 3; make sure `-RepetitionDuration` is not set to
  `[TimeSpan]::MaxValue`.
- **`Start-Service` / `Stop-Service` fails with access denied** — PowerShell
  must be running elevated (as Administrator).
- **Monitor task runs but never restarts the tunnel** — confirm the tunnel is
  installed as a Windows service (`Get-Service -Name "WireGuardTunnel*"`),
  not just running via the GUI in a user session; `SYSTEM` can only control
  the service form.
- **Log file never appears** — it's created on first write by
  `Monitor-WireGuardTunnel.ps1`; check the scheduled task actually ran via
  `Get-ScheduledTaskInfo` (`LastRunTime`, `LastTaskResult`).