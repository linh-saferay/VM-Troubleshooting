# -------------------------------------------------------------
# WireGuard DPAPI Unified Management Script
# -------------------------------------------------------------
[CmdletBinding(DefaultParameterSetName = "Start")]
param(
    [Parameter(ParameterSetName = "Start")][Switch]$Start,
    [Parameter(ParameterSetName = "Stop")][Switch]$Stop,
    [Parameter(ParameterSetName = "Restart")][Switch]$Restart,
    
    [String]$TunnelName    = "srjp", # Replace with your exact tunnel name
    [String]$DpapiFilePath = "C:\Program Files\WireGuard\Data\Configurations\srjp.conf.dpapi"
)

# 1. Check for Administrative Privileges
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "This script must be run as an Administrator!"
    Exit
}

$ServiceName = "WireGuardTunnel`$$TunnelName"
$Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if (-not $Service) {
    Write-Error "WireGuard service '$ServiceName' not found. Is it installed?"
    Exit
}

# 2. Determine Action (Default to Start if no switch is passed)
$Action = "Start"
if ($Stop) { $Action = "Stop" }
elseif ($Restart) { $Action = "Restart" }

# 3. Execute Actions
switch ($Action) {
    "Stop" {
        if ($Service.Status -eq 'Running') {
            Write-Host "Stopping WireGuard Service..." -ForegroundColor Yellow
            Stop-Service -Name $ServiceName
            Write-Host "Tunnel stopped." -ForegroundColor Green
        } else {
            Write-Host "WireGuard service is already stopped." -ForegroundColor Gray
        }
    }
    
    "Restart" {
        Write-Host "Restarting WireGuard Service..." -ForegroundColor Cyan
        Restart-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
        $InjectConfig = $true
    }
    
    "Start" {
        if ($Service.Status -ne 'Running') {
            Write-Host "Starting WireGuard Service..." -ForegroundColor Cyan
            Start-Service -Name $ServiceName
            Start-Sleep -Seconds 2
            $InjectConfig = $true
        } else {
            Write-Host "Service is already running. Re-applying configuration just in case..." -ForegroundColor Cyan
            $InjectConfig = $true
        }
    }
}

# 4. Decrypt and Inject configuration (Only for Start and Restart)
if ($InjectConfig) {
    Write-Host "Decrypting WireGuard configuration..." -ForegroundColor Cyan
    try {
        $EncryptedBytes = [System.IO.File]::ReadAllBytes($DpapiFilePath)
        $DecryptedBytes = [System.Security.Cryptography.ProtectedData]::Unprotect($EncryptedBytes, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
        $CleartextConfig = [System.Text.Encoding]::UTF8.GetString($DecryptedBytes)
    }
    catch {
        Write-Error "Failed to decrypt DPAPI file. Ensure you are logged into the correct Windows User account."
        Exit
    }

    Write-Host "Injecting secure configuration into $TunnelName..." -ForegroundColor Green
    $CleartextConfig | & "C:\Program Files\WireGuard\wg.exe" syncconf $TunnelName /dev/stdin
    Write-Host "Tunnel is successfully secured and active!" -ForegroundColor Green
}
