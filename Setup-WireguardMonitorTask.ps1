<#
.SYNOPSIS
    Registers a Task Scheduler task that periodically runs Monitor-WireGuardTunnel.ps1.

.DESCRIPTION
    Creates (or replaces) a scheduled task that runs as SYSTEM with highest privileges,
    repeating every -IntervalMinutes, indefinitely. Must be run as Administrator.

.PARAMETER ScriptPath
    Full path to Monitor-WireGuardTunnel.ps1. Default: same folder as this script.

.PARAMETER TunnelName
    Tunnel name to pass through to the monitor script. Default: srjp

.PARAMETER TargetIP
    IP to ping, passed through to the monitor script. Default: 10.9.0.1

.PARAMETER IntervalMinutes
    How often the task runs. Default: 5

.PARAMETER TaskName
    Name of the scheduled task. Default: "WireGuard Tunnel Monitor"

.EXAMPLE
    .\Setup-WireGuardMonitorTask.ps1
    .\Setup-WireGuardMonitorTask.ps1 -TunnelName srjp -TargetIP 10.9.0.1 -IntervalMinutes 5
#>

[CmdletBinding()]
param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "Monitor-WireGuardTunnel.ps1"),
    [string]$TunnelName = "srjp",
    [string]$TargetIP = "10.9.0.1",
    [int]$IntervalMinutes = 5,
    [string]$TaskName = "WireGuard Tunnel Monitor"
)

# Require elevation
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Monitor script not found at '$ScriptPath'. Place Monitor-WireGuardTunnel.ps1 there, or pass -ScriptPath."
    exit 1
}

# Remove existing task with the same name, if any
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Existing task '$TaskName' found - removing it before re-creating." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -TunnelName `"$TunnelName`" -TargetIP `"$TargetIP`""

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argumentList

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
# No -RepetitionDuration specified => repeats indefinitely (Task Scheduler default).
# [TimeSpan]::MaxValue is intentionally NOT used here - it serializes to an
# out-of-range duration (P99999999DT23H59M59S) that Register-ScheduledTask rejects.

$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew

try {
    Register-ScheduledTask -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "Pings $TargetIP every $IntervalMinutes min and restarts the '$TunnelName' WireGuard tunnel if it's unreachable." `
        -ErrorAction Stop | Out-Null
}
catch {
    Write-Error "Failed to register task '$TaskName': $($_.Exception.Message)"
    exit 1
}

Write-Host "Task '$TaskName' created successfully. Runs every $IntervalMinutes minute(s) as SYSTEM." -ForegroundColor Green
Get-ScheduledTask -TaskName $TaskName | Select-Object TaskName, State