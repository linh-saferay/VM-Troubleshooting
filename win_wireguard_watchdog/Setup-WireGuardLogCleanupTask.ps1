<#
.SYNOPSIS
    Registers a Task Scheduler task that prunes the WireGuard monitor log daily,
    keeping only the last -RetentionDays days of entries.

.DESCRIPTION
    Creates (or replaces) a scheduled task that runs once a day and calls
    Prune-WireGuardLog.ps1 to drop log lines older than the retention window.
    Runs as SYSTEM. Must be run as Administrator.

.PARAMETER ScriptPath
    Full path to Prune-WireGuardLog.ps1. Default: same folder as this script.

.PARAMETER LogPath
    Path to the log file to prune. Default: C:\WireGuardMonitor\wireguard-monitor.log

.PARAMETER RetentionDays
    Number of days of log history to keep. Default: 30

.PARAMETER At
    Time of day to run, e.g. "03:00". Default: "09:30"

.PARAMETER TaskName
    Name of the scheduled task. Default: "WireGuard Log Cleanup"

.EXAMPLE
    .\Setup-WireGuardLogCleanupTask.ps1
    .\Setup-WireGuardLogCleanupTask.ps1 -RetentionDays 30 -At "03:00"
#>

[CmdletBinding()]
param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "Prune-WireGuardLog.ps1"),
    [string]$LogPath = "C:\WireGuardMonitor\wireguard-monitor.log",
    [int]$RetentionDays = 30,
    [string]$At = "09:30",
    [string]$TaskName = "WireGuard Log Cleanup"
)

# Require elevation
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Prune script not found at '$ScriptPath'. Place Prune-WireGuardLog.ps1 there, or pass -ScriptPath."
    exit 1
}

# Remove existing task with the same name, if any
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Existing task '$TaskName' found - removing it before re-creating." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -LogPath `"$LogPath`" -RetentionDays $RetentionDays"

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argumentList

$trigger = New-ScheduledTaskTrigger -Daily -At $At

$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

try {
    Register-ScheduledTask -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "Keeps the last $RetentionDays days of '$LogPath', pruning older entries daily." `
        -ErrorAction Stop | Out-Null
}
catch {
    Write-Error "Failed to register task '$TaskName': $($_.Exception.Message)"
    exit 1
}

Write-Host "Task '$TaskName' created successfully. Runs daily at $At, keeps last $RetentionDays days of '$LogPath'." -ForegroundColor Green
Get-ScheduledTask -TaskName $TaskName | Select-Object TaskName, State