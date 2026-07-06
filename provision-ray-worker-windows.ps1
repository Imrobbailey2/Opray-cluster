# ==============================================================
# Opray Cluster - Windows Worker Provisioning Script
# "Insomnia" mode: machine stays awake and joins the cluster
# at boot even when no user is logged in.
#
# Run this in PowerShell (Admin) on any new Windows 11 worker.
# ==============================================================

# ── Configurable Variables ────────────────────────────────────
$WSL2MemoryGB  = "16GB"   # Tune to machine RAM
$WSL2Processors = 12      # Reserve cores for Ray

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Opray Cluster - Windows Worker Provisioning  " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# -- 1/5 Insomnia Power Profile --------------------------------
Write-Host "[ 1/5 ] Configuring Insomnia power profile..." -ForegroundColor Yellow

powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /change disk-timeout-ac 0
powercfg /change monitor-timeout-ac 60
powercfg /h off

Write-Host "  OK  Sleep disabled (AC power)" -ForegroundColor Green
Write-Host "  OK  Hibernate disabled (AC power)" -ForegroundColor Green
Write-Host "  OK  Disk timeout disabled (AC power)" -ForegroundColor Green
Write-Host "  OK  Monitor timeout set to 60 minutes" -ForegroundColor Green
Write-Host "  OK  Hibernate file removed" -ForegroundColor Green

# -- 2/5 Defer Windows Update Auto-Restart ---------------------
Write-Host ""
Write-Host "[ 2/5 ] Deferring Windows Update auto-restarts..." -ForegroundColor Yellow

$wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (-not (Test-Path $wuPath)) {
    New-Item -Path $wuPath -Force | Out-Null
}
Set-ItemProperty -Path $wuPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $wuPath -Name "AUOptions"                     -Value 4 -Type DWord -Force

Write-Host "  OK  NoAutoRebootWithLoggedOnUsers = 1" -ForegroundColor Green
Write-Host "  OK  AUOptions = 4 (notify only, no auto-install)" -ForegroundColor Green

# -- 3/5 WSL2 Mirrored Networking ------------------------------
Write-Host ""
Write-Host "[ 3/5 ] Configuring WSL2 networking and resources..." -ForegroundColor Yellow

@"
[wsl2]
memory=$WSL2MemoryGB
processors=$WSL2Processors
networkingMode=mirrored
autoProxy=true
kernelCommandLine=systemd.unified_cgroup_hierarchy=1
"@ | Set-Content "$env:USERPROFILE\.wslconfig"

Write-Host "  OK  .wslconfig written to $env:USERPROFILE\.wslconfig" -ForegroundColor Green
Write-Host "  OK  memory=$WSL2MemoryGB, processors=$WSL2Processors" -ForegroundColor Green
Write-Host "  OK  networkingMode=mirrored (Tailscale-compatible)" -ForegroundColor Green

# -- 4/5 Windows Firewall Rules --------------------------------
Write-Host ""
Write-Host "[ 4/5 ] Creating Ray firewall rules..." -ForegroundColor Yellow

$ports = @(
    @{Name="Opray-GCS";         Port=6379},
    @{Name="Opray-Dashboard";   Port=8265},
    @{Name="Opray-Client";      Port=10001},
    @{Name="Opray-ObjManager";  Port=10002},
    @{Name="Opray-NodeManager"; Port=20001}
)

foreach ($p in $ports) {
    $existing = Get-NetFirewallRule -DisplayName $p.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  --  Rule already exists: $($p.Name)" -ForegroundColor Gray
    } else {
        New-NetFirewallRule `
            -DisplayName $p.Name `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $p.Port `
            -Action Allow `
            -Profile Any `
            -Enabled True | Out-Null
        Write-Host "  OK  $($p.Name) port $($p.Port)" -ForegroundColor Green
    }
}

$existingRange = Get-NetFirewallRule -DisplayName "Opray-WorkerRange" -ErrorAction SilentlyContinue
if ($existingRange) {
    Write-Host "  --  Rule already exists: Opray-WorkerRange" -ForegroundColor Gray
} else {
    New-NetFirewallRule `
        -DisplayName "Opray-WorkerRange" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 20002-20100 `
        -Action Allow `
        -Profile Any `
        -Enabled True | Out-Null
    Write-Host "  OK  Opray-WorkerRange ports 20002-20100" -ForegroundColor Green
}

# -- 5/5 Scheduled Tasks and Helper Scripts --------------------
Write-Host ""
Write-Host "[ 5/5 ] Creating scheduled tasks and helper scripts..." -ForegroundColor Yellow

$dataDir = "C:\ProgramData\Opray-cluster"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir | Out-Null
    Write-Host "  OK  Created $dataDir" -ForegroundColor Green
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($file in @("ray-worker-notify.ps1", "ray-worker-resume.ps1")) {
    $src = Join-Path $scriptDir $file
    $dst = Join-Path $dataDir $file
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        Write-Host "  OK  Copied $file to $dataDir" -ForegroundColor Green
    } else {
        Write-Host "  WARN  $file not found next to provisioning script - download manually if needed" -ForegroundColor Yellow
    }
}

# Task a: RayWorkerBoot (SYSTEM, AtStartup)
$bootAction = New-ScheduledTaskAction `
    -Execute "wsl.exe" `
    -Argument "-u robbailey -e bash -c '~/scripts/ray-worker-autostart.sh'"

$bootTrigger = New-ScheduledTaskTrigger -AtStartup
$bootTrigger.Delay = "PT60S"

$bootSettings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable

$bootPrincipal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

$existing = Get-ScheduledTask -TaskPath "\Opray\" -TaskName "RayWorkerBoot" -ErrorAction SilentlyContinue
if ($existing) { Unregister-ScheduledTask -TaskPath "\Opray\" -TaskName "RayWorkerBoot" -Confirm:$false }
Register-ScheduledTask `
    -TaskName "RayWorkerBoot" `
    -TaskPath "\Opray\" `
    -Action $bootAction `
    -Trigger $bootTrigger `
    -Settings $bootSettings `
    -Principal $bootPrincipal `
    -Description "Opray: Starts Ray GPU worker at system boot (insomnia mode)" | Out-Null
Write-Host "  OK  Task created: \Opray\RayWorkerBoot" -ForegroundColor Green

# Task b: RayWorkerNotify (Users, AtLogon)
$notifyAction = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dataDir\ray-worker-notify.ps1`""

$notifyTrigger = New-ScheduledTaskTrigger -AtLogOn

$notifySettings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
    -StartWhenAvailable

$notifyPrincipal = New-ScheduledTaskPrincipal `
    -GroupId "BUILTIN\Users" `
    -RunLevel Highest

$existing = Get-ScheduledTask -TaskPath "\Opray\" -TaskName "RayWorkerNotify" -ErrorAction SilentlyContinue
if ($existing) { Unregister-ScheduledTask -TaskPath "\Opray\" -TaskName "RayWorkerNotify" -Confirm:$false }
Register-ScheduledTask `
    -TaskName "RayWorkerNotify" `
    -TaskPath "\Opray\" `
    -Action $notifyAction `
    -Trigger $notifyTrigger `
    -Settings $notifySettings `
    -Principal $notifyPrincipal `
    -Description "Opray: Notifies logged-in user that this machine is an active cluster worker" | Out-Null
Write-Host "  OK  Task created: \Opray\RayWorkerNotify" -ForegroundColor Green

# Task c: RayWorkerResume (SYSTEM, Winlogon Event 7002)
$resumeAction = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File `"$dataDir\ray-worker-resume.ps1`""

$resumeTrigger = New-CimInstance -ClassName MSFT_TaskEventTrigger `
    -Namespace Root/Microsoft/Windows/TaskScheduler `
    -ClientOnly `
    -Property @{
        Enabled      = $true
        Subscription = "<QueryList><Query Id='0' Path='System'><Select Path='System'>*[System[Provider[@Name='Microsoft-Windows-Winlogon'] and EventID=7002]]</Select></Query></QueryList>"
    }

$resumeSettings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -StartWhenAvailable

$resumePrincipal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

$existing = Get-ScheduledTask -TaskPath "\Opray\" -TaskName "RayWorkerResume" -ErrorAction SilentlyContinue
if ($existing) { Unregister-ScheduledTask -TaskPath "\Opray\" -TaskName "RayWorkerResume" -Confirm:$false }
Register-ScheduledTask `
    -TaskName "RayWorkerResume" `
    -TaskPath "\Opray\" `
    -Action $resumeAction `
    -Trigger $resumeTrigger `
    -Settings $resumeSettings `
    -Principal $resumePrincipal `
    -Description "Opray: Resumes Ray worker after user locks screen or signs out" | Out-Null
Write-Host "  OK  Task created: \Opray\RayWorkerResume" -ForegroundColor Green

# -- Summary ---------------------------------------------------
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Provisioning Complete                        " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Power:     Insomnia mode active (no sleep/hibernate)" -ForegroundColor White
Write-Host "  Updates:   Windows Update auto-restart deferred" -ForegroundColor White
Write-Host "  Network:   WSL2 mirrored networking configured ($WSL2MemoryGB RAM, $WSL2Processors cores)" -ForegroundColor White
Write-Host "  Firewall:  Ray ports open (All profiles)" -ForegroundColor White
Write-Host "  Tasks:     RayWorkerBoot, RayWorkerNotify, RayWorkerResume" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "    1. Install Tailscale (Windows app) and authenticate to Imrobbailey2@ account" -ForegroundColor White
Write-Host "    2. Restart WSL2:" -ForegroundColor White
Write-Host "       wsl --shutdown" -ForegroundColor Gray
Write-Host "    3. Open Ubuntu and run:" -ForegroundColor White
Write-Host "       git clone https://github.com/Imrobbailey2/Opray-cluster.git" -ForegroundColor Gray
Write-Host "       bash Opray-cluster/provision-ray-worker.sh" -ForegroundColor Gray
Write-Host ""
Write-Host "  This machine will auto-join the cluster on next reboot." -ForegroundColor Green
Write-Host ""
