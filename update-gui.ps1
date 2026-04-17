Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ManifestUrl = 'https://raw.githubusercontent.com/1IDKey/GG/main/manifest.json'
$ModsDir = Join-Path $env:APPDATA '.minecraft\versions\GG\mods'

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GG Modpack Updater'
$form.Size = New-Object System.Drawing.Size(640, 480)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = 'GG Modpack Updater'
$lblHeader.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblHeader.Location = New-Object System.Drawing.Point(12, 12)
$lblHeader.Size = New-Object System.Drawing.Size(600, 28)
$form.Controls.Add($lblHeader)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Ready.'
$lblStatus.Location = New-Object System.Drawing.Point(12, 48)
$lblStatus.Size = New-Object System.Drawing.Size(600, 20)
$form.Controls.Add($lblStatus)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(12, 72)
$progress.Size = New-Object System.Drawing.Size(600, 22)
$progress.Style = 'Continuous'
$form.Controls.Add($progress)

$lblCurrent = New-Object System.Windows.Forms.Label
$lblCurrent.Text = ''
$lblCurrent.Location = New-Object System.Drawing.Point(12, 100)
$lblCurrent.Size = New-Object System.Drawing.Size(600, 20)
$lblCurrent.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblCurrent)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ScrollBars = 'Vertical'
$log.ReadOnly = $true
$log.Location = New-Object System.Drawing.Point(12, 128)
$log.Size = New-Object System.Drawing.Size(600, 260)
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$log.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($log)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = 'Update'
$btnUpdate.Location = New-Object System.Drawing.Point(432, 398)
$btnUpdate.Size = New-Object System.Drawing.Size(85, 32)
$form.Controls.Add($btnUpdate)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(527, 398)
$btnClose.Size = New-Object System.Drawing.Size(85, 32)
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

function Write-Log {
    param($msg)
    $log.AppendText("$msg`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Status {
    param($msg)
    $lblStatus.Text = $msg
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Current {
    param($msg)
    $lblCurrent.Text = $msg
    [System.Windows.Forms.Application]::DoEvents()
}

$btnUpdate.Add_Click({
    $btnUpdate.Enabled = $false
    $btnClose.Enabled = $false
    $log.Clear()
    $progress.Value = 0
    Set-Current ''

    try {
        if (-not (Test-Path $ModsDir)) {
            Set-Status 'Error: mods folder not found.'
            Write-Log "Expected: $ModsDir"
            Write-Log 'Install version GG and launch the game at least once.'
            return
        }

        Set-Status 'Fetching manifest...'
        Write-Log "Manifest: $ManifestUrl"
        $ProgressPreference = 'SilentlyContinue'
        $manifest = Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing

        $wanted = @{}
        foreach ($m in $manifest.mods) { $wanted[$m.filename] = $m }

        $current = Get-ChildItem -Path $ModsDir -Filter *.jar -File
        $currentMap = @{}
        foreach ($f in $current) { $currentMap[$f.Name] = $f }

        $toDelete   = @($current | Where-Object { -not $wanted.ContainsKey($_.Name) })
        $toDownload = @()
        foreach ($m in $manifest.mods) {
            if (-not $currentMap.ContainsKey($m.filename)) {
                $toDownload += $m
            } elseif ($m.size -and $currentMap[$m.filename].Length -ne [long]$m.size) {
                $toDownload += $m
            }
        }

        Write-Log "Manifest version: $($manifest.version)"
        Write-Log "In manifest:  $($manifest.mods.Count)"
        Write-Log "To delete:    $($toDelete.Count)"
        Write-Log "To download:  $($toDownload.Count)"
        Write-Log ''

        if ($toDelete.Count -eq 0 -and $toDownload.Count -eq 0) {
            Set-Status 'Already up to date.'
            $progress.Value = 100
            return
        }

        foreach ($f in $toDelete) {
            Write-Log "- $($f.Name)"
            Remove-Item $f.FullName -Force
        }

        $total = $toDownload.Count
        if ($total -eq 0) {
            Set-Status 'Done.'
            $progress.Value = 100
            return
        }

        Set-Status "Downloading $total mod(s)..."
        $i = 0
        foreach ($m in $toDownload) {
            $i++
            $dest = Join-Path $ModsDir $m.filename
            $sizeMb = if ($m.size) { [math]::Round($m.size / 1MB, 1) } else { '?' }
            Set-Current "[$i/$total] $($m.filename) ($sizeMb MB)"
            Write-Log "+ $($m.filename)"
            try {
                Invoke-WebRequest -Uri $m.url -OutFile $dest -UseBasicParsing
            } catch {
                Write-Log "  ERROR: $($_.Exception.Message)"
                if (Test-Path $dest) { Remove-Item $dest -Force }
            }
            $progress.Value = [int](($i / $total) * 100)
            [System.Windows.Forms.Application]::DoEvents()
        }

        Set-Current ''
        Set-Status "Done. Updated $total mod(s)."
    } catch {
        Set-Status "Error: $($_.Exception.Message)"
        Write-Log $_.Exception.Message
    } finally {
        $btnUpdate.Enabled = $true
        $btnClose.Enabled = $true
    }
})

[void]$form.ShowDialog()
