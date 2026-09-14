<#
.SYNOPSIS
    Pings a target IP through a WireGuard tunnel and restarts the tunnel service if the ping fails.

.DESCRIPTION
    Intended to be run periodically (via Task Scheduler) to auto-heal a WireGuard tunnel.
    Sends a small burst of pings to -TargetIP; if all of them fail, restarts the
    WireGuardTunnel$<TunnelName> service and logs the event.

.PARAMETER TunnelName
    The tunnel name (matches the .conf filename without extension). Default: srjp

.PARAMETER TargetIP
    IP address to ping to verify the tunnel is up. Default: 10.9.0.1

.PARAMETER PingCount
    Number of pings to send before declaring failure. Default: 4

.PARAMETER LogPath
    Path to the log file. Default: C:\WireGuardMonitor\wireguard-monitor.log

.EXAMPLE
    .\Monitor-WireGuardTunnel.ps1 -TunnelName srjp -TargetIP 10.9.0.1
#>

[CmdletBinding()]
param(
    [string]$TunnelName = "srjp",
    [string]$TargetIP = "10.9.0.1",
    [int]$PingCount = 4,
    [string]$LogPath = "C:\WireGuardMonitor\wireguard-monitor.log"
)

$ServiceName = "WireGuardTunnel`$$TunnelName"

function Write-Log {
    param([string]$Message)
    $logDir = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp  $Message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
}

$pingOk = Test-Connection -ComputerName $TargetIP -Count $PingCount -Quiet -ErrorAction SilentlyContinue

if ($pingOk) {
    Write-Log "OK - $TargetIP reachable via tunnel '$TunnelName'."
    exit 0
}

Write-Log "FAIL - $TargetIP unreachable ($PingCount/$PingCount pings lost). Restarting service '$ServiceName'..."

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Log "ERROR - Service '$ServiceName' not found. Cannot restart."
    exit 1
}

try {
    Restart-Service -Name $ServiceName -ErrorAction Stop
    Start-Sleep -Seconds 5
    $recheck = Test-Connection -ComputerName $TargetIP -Count $PingCount -Quiet -ErrorAction SilentlyContinue
    if ($recheck) {
        Write-Log "RECOVERED - Tunnel '$TunnelName' restarted successfully, $TargetIP now reachable."
    } else {
        Write-Log "WARNING - Tunnel '$TunnelName' restarted, but $TargetIP still unreachable."
    }
}
catch {
    Write-Log "ERROR - Failed to restart service '$ServiceName': $($_.Exception.Message)"
    exit 1
}