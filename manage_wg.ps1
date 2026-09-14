<#
.SYNOPSIS
    Start, stop, restart, or check the status of a WireGuard tunnel service on Windows.

.DESCRIPTION
    Wraps Start-Service / Stop-Service / Restart-Service for a WireGuard tunnel
    installed as a Windows service (WireGuardTunnel$<Name>).
    Must be run as Administrator.

.PARAMETER Action
    One of: Start, Stop, Restart, Status

.PARAMETER TunnelName
    The tunnel name (matches the .conf filename without extension).
    Defaults to "srjp".

.EXAMPLE
    .\Manage-WireGuardTunnel.ps1 -Action Start
    .\Manage-WireGuardTunnel.ps1 -Action Stop -TunnelName srjp
    .\Manage-WireGuardTunnel.ps1 -Action Restart
    .\Manage-WireGuardTunnel.ps1 -Action Status

.EXAMPLE
    From bash:
    powershell.exe -Command "& 'C:\path\to\Manage-WireGuardTunnel.ps1' -Action Start -TunnelName srjp"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("Start", "Stop", "Restart", "Status")]
    [string]$Action,

    [Parameter(Position = 1)]
    [string]$TunnelName = "srjp"
)

# Require elevation
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Re-launch PowerShell with elevated privileges."
    exit 1
}

$ServiceName = "WireGuardTunnel`$$TunnelName"

# Verify the service exists
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Error "Service '$ServiceName' not found. Check the tunnel name, or import/activate the tunnel first in the WireGuard GUI."
    exit 1
}

switch ($Action) {
    "Start" {
        Write-Host "Starting tunnel '$TunnelName'..." -ForegroundColor Cyan
        Start-Service -Name $ServiceName
        Write-Host "Tunnel '$TunnelName' started." -ForegroundColor Green
    }
    "Stop" {
        Write-Host "Stopping tunnel '$TunnelName'..." -ForegroundColor Cyan
        Stop-Service -Name $ServiceName
        Write-Host "Tunnel '$TunnelName' stopped." -ForegroundColor Green
    }
    "Restart" {
        Write-Host "Restarting tunnel '$TunnelName'..." -ForegroundColor Cyan
        Restart-Service -Name $ServiceName
        Write-Host "Tunnel '$TunnelName' restarted." -ForegroundColor Green
    }
    "Status" {
        Get-Service -Name $ServiceName | Select-Object Name, Status, DisplayName | Format-Table -AutoSize
    }
}

# Show final status (except when Status was already printed above)
if ($Action -ne "Status") {
    Get-Service -Name $ServiceName | Select-Object Name, Status | Format-Table -AutoSize
}