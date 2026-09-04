# create-watchdog-tasks.ps1
# Tao 2 scheduled task: host_vm_watchdog (chay dinh ky) va ssh_keepalive_vm (chay luc startup)
# Chay script nay voi quyen Administrator

$WinUsername = $env:USERNAME
$BashExe = "C:\Program Files\Git\usr\bin\bash.exe"
$ScriptDir = "C:\Users\$WinUsername\scripts"

$WatchdogScript = "$ScriptDir\host_vm_watchdog.sh"
$KeepaliveScript = "$ScriptDir\ssh-keepalive.sh"

$WatchdogTaskName = "host_vm_watchdog"
$KeepaliveTaskName = "ssh_keepalive_vm"

$WatchdogIntervalMinutes = 30   # doi neu can chay voi tan suat khac

Write-Host "Username: $WinUsername"
Write-Host "Bash path: $BashExe"
Write-Host "Watchdog script: $WatchdogScript"
Write-Host "Keepalive script: $KeepaliveScript"
Write-Host ""

# Kiem tra bash.exe va script ton tai
if (-not (Test-Path $BashExe)) {
    Write-Host "ERROR: Khong tim thay bash.exe tai $BashExe" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $WatchdogScript)) {
    Write-Host "ERROR: Khong tim thay $WatchdogScript" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $KeepaliveScript)) {
    Write-Host "ERROR: Khong tim thay $KeepaliveScript" -ForegroundColor Red
    exit 1
}

# Chuyen path Windows sang dinh dang Git Bash (C:\Users\... -> /c/Users/...)
function Convert-ToBashPath($winPath) {
    $p = $winPath -replace '\\', '/'
    $p = $p -replace '^([A-Za-z]):', { "/" + $_.Groups[1].Value.ToLower() }
    return $p
}

$WatchdogScriptBash = Convert-ToBashPath $WatchdogScript
$KeepaliveScriptBash = Convert-ToBashPath $KeepaliveScript

Write-Host "Bash path cho watchdog: $WatchdogScriptBash"
Write-Host "Bash path cho keepalive: $KeepaliveScriptBash"
Write-Host ""

# Xoa task cu neu co (de tao lai sach)
schtasks /delete /tn "$WatchdogTaskName" /f 2>$null
schtasks /delete /tn "$KeepaliveTaskName" /f 2>$null

Write-Host "Nhap password cho user $WinUsername khi duoc hoi..." -ForegroundColor Yellow
Write-Host ""

# Task 1: host_vm_watchdog - chay dinh ky moi X phut
Write-Host "Tao task: $WatchdogTaskName (chay moi $WatchdogIntervalMinutes phut)"
schtasks /create /tn "$WatchdogTaskName" `
    /tr "'$BashExe' -c '$WatchdogScriptBash'" `
    /sc minute /mo $WatchdogIntervalMinutes `
    /ru "$WinUsername" /rp *

if ($LASTEXITCODE -ne 0) {
    Write-Host "Loi khi tao task $WatchdogTaskName" -ForegroundColor Red
} else {
    Write-Host "Da tao thanh cong: $WatchdogTaskName" -ForegroundColor Green
}
Write-Host ""

# Task 2: ssh_keepalive_vm - chay luc startup, giu chay mai (khong repeat interval)
Write-Host "Tao task: $KeepaliveTaskName (chay luc startup)"
schtasks /create /tn "$KeepaliveTaskName" `
    /tr "'$BashExe' -c '$KeepaliveScriptBash'" `
    /sc onstart `
    /ru "$WinUsername" /rp *

if ($LASTEXITCODE -ne 0) {
    Write-Host "Loi khi tao task $KeepaliveTaskName" -ForegroundColor Red
} else {
    Write-Host "Da tao thanh cong: $KeepaliveTaskName" -ForegroundColor Green
}
Write-Host ""

# Set task chay du user co logon hay khong, va quyen cao nhat
Write-Host "Cau hinh 'Run whether user is logged on or not' cho ca 2 task..."
$principalWatchdog = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$WinUsername" -LogonType S4U -RunLevel Highest
Set-ScheduledTask -TaskName "$WatchdogTaskName" -Principal $principalWatchdog -ErrorAction SilentlyContinue

$principalKeepalive = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$WinUsername" -LogonType S4U -RunLevel Highest
Set-ScheduledTask -TaskName "$KeepaliveTaskName" -Principal $principalKeepalive -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Hoan tat. Kiem tra lai bang:" -ForegroundColor Cyan
Write-Host "  Get-ScheduledTaskInfo -TaskName '$WatchdogTaskName'"
Write-Host "  Get-ScheduledTaskInfo -TaskName '$KeepaliveTaskName'"
