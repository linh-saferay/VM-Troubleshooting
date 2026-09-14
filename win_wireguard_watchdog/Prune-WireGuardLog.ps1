<#
.SYNOPSIS
    Removes log entries older than a retention period from the WireGuard monitor log.

.DESCRIPTION
    Reads the log file, keeps only lines whose leading timestamp is within the
    last -RetentionDays days, and rewrites the file. Lines that don't match the
    expected timestamp format are kept as-is (fail-safe, avoids accidental data loss).

.PARAMETER LogPath
    Path to the log file. Default: C:\WireGuardMonitor\wireguard-monitor.log

.PARAMETER RetentionDays
    Number of days of log history to keep. Default: 30

.EXAMPLE
    .\Prune-WireGuardLog.ps1
    .\Prune-WireGuardLog.ps1 -RetentionDays 30
#>

[CmdletBinding()]
param(
    [string]$LogPath = "C:\WireGuardMonitor\wireguard-monitor.log",
    [int]$RetentionDays = 30
)

if (-not (Test-Path $LogPath)) {
    # Nothing to prune yet
    exit 0
}

$cutoff = (Get-Date).AddDays(-$RetentionDays)

$kept = Get-Content -Path $LogPath | Where-Object {
    if ($_ -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
        try {
            [datetime]::ParseExact($matches[1], "yyyy-MM-dd HH:mm:ss", $null) -ge $cutoff
        }
        catch {
            # Unparseable timestamp - keep the line rather than risk losing data
            $true
        }
    }
    else {
        # Line doesn't start with a timestamp (e.g. blank line) - keep it
        $true
    }
}

Set-Content -Path $LogPath -Value $kept -Encoding UTF8