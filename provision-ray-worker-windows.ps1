# Run this in PowerShell (Admin) on any new Windows 11 worker machine
# Sets up WSL2 mirrored networking and Ray firewall rules

# Step 1 - Mirrored networking
@"
[wsl2]
networkingMode=mirrored
autoProxy=true
"@ | Set-Content "$env:USERPROFILE\.wslconfig"

# Step 2 - Ray firewall rules (Domain profile)
$ports = @(
    @{Name="Ray-GCS";         Port=6379},
    @{Name="Ray-Dashboard";   Port=8265},
    @{Name="Ray-Client";      Port=10001},
    @{Name="Ray-ObjManager";  Port=10002},
    @{Name="Ray-NodeManager"; Port=20001}
)

foreach ($p in $ports) {
    New-NetFirewallRule `
        -DisplayName $p.Name `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $p.Port `
        -Action Allow `
        -Profile Domain `
        -Enabled True
    Write-Host "OK: $($p.Name) port $($p.Port)"
}

New-NetFirewallRule `
    -DisplayName "Ray-WorkerRange" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 20002-20100 `
    -Action Allow `
    -Profile Domain `
    -Enabled True

Write-Host ""
Write-Host "Windows provisioning complete. Now restart WSL2:"
Write-Host "  wsl --shutdown"
Write-Host "Then run in WSL2:"
Write-Host "  bash Opray-cluster/provision-ray-worker.sh <HEAD_IP>"
