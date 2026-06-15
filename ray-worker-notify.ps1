# ==============================================================
# Opray Cluster - Worker Notification Script
# Displayed at user login when machine is an active cluster worker
# Triggered by: \Opray\RayWorkerNotify scheduled task
# ==============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$countdown = 30

# -- Form --
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Opray Cluster - Active Worker'
$form.Size            = New-Object System.Drawing.Size(440, 220)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.TopMost         = $true
$form.BackColor       = [System.Drawing.Color]::White

# -- Icon --
$iconBox = New-Object System.Windows.Forms.PictureBox
$iconBox.Size     = New-Object System.Drawing.Size(48, 48)
$iconBox.Location = New-Object System.Drawing.Point(16, 16)
$iconBox.Image    = [System.Drawing.SystemIcons]::Information.ToBitmap()
$iconBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
$form.Controls.Add($iconBox)

# -- Message Label --
$label = New-Object System.Windows.Forms.Label
$label.Text     = "This machine is active as a GPU worker in the`nOpray distributed compute cluster.`n`nYou may pause cluster membership while you work.`nMembership resumes automatically when you lock or sign out."
$label.Location = New-Object System.Drawing.Point(76, 14)
$label.Size     = New-Object System.Drawing.Size(340, 100)
$label.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Controls.Add($label)

# -- Countdown Label --
$countLabel = New-Object System.Windows.Forms.Label
$countLabel.Text      = 'Auto-continuing in 30s...'
$countLabel.Location  = New-Object System.Drawing.Point(76, 118)
$countLabel.Size      = New-Object System.Drawing.Size(280, 20)
$countLabel.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
$countLabel.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($countLabel)

# -- Pause Button --
$pauseBtn = New-Object System.Windows.Forms.Button
$pauseBtn.Text     = 'Pause Membership'
$pauseBtn.Size     = New-Object System.Drawing.Size(160, 34)
$pauseBtn.Location = New-Object System.Drawing.Point(16, 142)
$pauseBtn.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
$pauseBtn.Add_Click({
    $timer.Stop()
    & wsl.exe -u robbailey -e bash -c 'touch /tmp/ray-paused && source ~/venvs/ray/bin/activate && ray stop --force 2>/dev/null || true'
    [System.Windows.Forms.MessageBox]::Show(
        "Cluster membership paused.`nIt will resume automatically when you lock or sign out.",
        'Opray Cluster',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    $form.Close()
})
$form.Controls.Add($pauseBtn)

# -- Continue Button --
$continueBtn = New-Object System.Windows.Forms.Button
$continueBtn.Text      = 'Continue as Worker'
$continueBtn.Size      = New-Object System.Drawing.Size(160, 34)
$continueBtn.Location  = New-Object System.Drawing.Point(252, 142)
$continueBtn.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
$continueBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$continueBtn.ForeColor = [System.Drawing.Color]::White
$continueBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$form.AcceptButton     = $continueBtn
$continueBtn.Add_Click({ $timer.Stop(); $form.Close() })
$form.Controls.Add($continueBtn)

# -- Countdown Timer --
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    $script:countdown--
    $countLabel.Text = "Auto-continuing in $($script:countdown)s..."
    if ($script:countdown -le 0) {
        $timer.Stop()
        $form.Close()
    }
})
$timer.Start()

# -- Show Form --
[System.Windows.Forms.Application]::Run($form)
$form.Dispose()
