# ==============================================================
# Opray Cluster - Worker Resume Script
# Triggered by Windows Winlogon Event ID 7002
# (user session disconnect: lock screen or sign out)
# Resumes Ray cluster membership after user pauses it.
# ==============================================================

$logFile = "C:\ProgramData\Opray-cluster\resume.log"

"$(Get-Date) -- Opray resume triggered (Winlogon Event 7002)" | Out-File -Append $logFile

# Wait for the session to fully disconnect before rejoining
Start-Sleep -Seconds 10

"$(Get-Date) -- Resuming Ray worker..." | Out-File -Append $logFile

& wsl.exe -u robbailey -e bash -c "rm -f /tmp/ray-paused && ~/scripts/ray-worker-autostart.sh"

"$(Get-Date) -- Ray worker resume complete" | Out-File -Append $logFile
