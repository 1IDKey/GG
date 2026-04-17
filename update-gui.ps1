Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ScriptVersion     = '1.1.0'
$ManifestUrl       = 'https://raw.githubusercontent.com/1IDKey/GG/main/manifest.json'
$ScriptRawBase     = 'https://raw.githubusercontent.com/1IDKey/GG/main'
$DefaultVersionDir = Join-Path $env:APPDATA '.minecraft\versions\GG'
$ConfigFile        = Join-Path $PSScriptRoot 'gg-updater.cfg'
$IgnoreFile        = Join-Path $PSScriptRoot 'ignore.txt'
$BackupKeep        = 5

function Test-MinecraftRunning {
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name='javaw.exe' OR Name='java.exe'" -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            if ($p.CommandLine -and ($p.CommandLine -match 'minecraft|forge|fabric|fml|modlauncher|bootstraplauncher')) {
                return $true
            }
        }
    } catch {}
    return $false
}

function Get-RemoteScriptVersion {
    try {
        $ProgressPreference = 'SilentlyContinue'
        $txt = (Invoke-WebRequest -Uri "$ScriptRawBase/update-gui.ps1" -UseBasicParsing -TimeoutSec 8).Content
        if ($txt -match "\`$ScriptVersion\s*=\s*'([^']+)'") { return $matches[1] }
    } catch {}
    return $null
}

function Load-Config {
    if (Test-Path $ConfigFile) {
        $p = (Get-Content $ConfigFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($p -and (Test-Path $p)) { return $p }
    }
    if (Test-Path $DefaultVersionDir) { return $DefaultVersionDir }
    return ''
}

function Save-Config { param($p) Set-Content -Path $ConfigFile -Value $p -Encoding ASCII }

function Resolve-ModsDir {
    param($versionDir)
    if (-not $versionDir) { return $null }
    $sub = Join-Path $versionDir 'mods'
    if (Test-Path $sub) { return $sub }
    return $null
}

function Load-IgnoreList {
    if (-not (Test-Path $IgnoreFile)) { return @() }
    return @(Get-Content $IgnoreFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
}

function Test-Ignored {
    param($name, $patterns)
    foreach ($p in $patterns) { if ($name -like $p) { return $true } }
    return $false
}

function Load-SyncState {
    param($versionDir)
    $path = Join-Path $versionDir '.gg-sync-state.json'
    if (Test-Path $path) {
        try { return Get-Content $path -Raw | ConvertFrom-Json } catch { return [PSCustomObject]@{} }
    }
    return [PSCustomObject]@{}
}

function Save-SyncState {
    param($versionDir, $state)
    $path = Join-Path $versionDir '.gg-sync-state.json'
    $state | ConvertTo-Json -Depth 4 | Set-Content -Path $path -Encoding UTF8
}

function New-Backup {
    param($sourceDir, $versionDir, $label)
    if (-not (Test-Path $sourceDir)) { return $null }
    $backupDir = Join-Path $versionDir 'backups'
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $zip = Join-Path $backupDir "$label-$stamp.zip"
    Compress-Archive -Path (Join-Path $sourceDir '*') -DestinationPath $zip -Force
    # Prune old
    $all = Get-ChildItem -Path $backupDir -Filter "$label-*.zip" -File | Sort-Object LastWriteTime -Descending
    if ($all.Count -gt $BackupKeep) {
        $all | Select-Object -Skip $BackupKeep | ForEach-Object { Remove-Item $_.FullName -Force }
    }
    return $zip
}

$script:VersionDir = Load-Config

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GG Modpack Updater'
$form.Size = New-Object System.Drawing.Size(640, 520)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = 'GG Modpack Updater'
$lblHeader.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblHeader.Location = New-Object System.Drawing.Point(12, 12)
$lblHeader.Size = New-Object System.Drawing.Size(380, 28)
$form.Controls.Add($lblHeader)

$lnkVersion = New-Object System.Windows.Forms.LinkLabel
$lnkVersion.Text = "v$ScriptVersion"
$lnkVersion.Location = New-Object System.Drawing.Point(400, 18)
$lnkVersion.Size = New-Object System.Drawing.Size(212, 20)
$lnkVersion.TextAlign = 'MiddleRight'
$lnkVersion.LinkBehavior = 'HoverUnderline'
$lnkVersion.Enabled = $false
$form.Controls.Add($lnkVersion)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = 'Version folder:'
$lblPath.Location = New-Object System.Drawing.Point(12, 46)
$lblPath.Size = New-Object System.Drawing.Size(100, 18)
$form.Controls.Add($lblPath)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(12, 66)
$txtPath.Size = New-Object System.Drawing.Size(510, 24)
$txtPath.ReadOnly = $true
$txtPath.Text = $script:VersionDir
$form.Controls.Add($txtPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse...'
$btnBrowse.Location = New-Object System.Drawing.Point(527, 65)
$btnBrowse.Size = New-Object System.Drawing.Size(85, 26)
$form.Controls.Add($btnBrowse)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Ready.'
$lblStatus.Location = New-Object System.Drawing.Point(12, 100)
$lblStatus.Size = New-Object System.Drawing.Size(600, 20)
$form.Controls.Add($lblStatus)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(12, 124)
$progress.Size = New-Object System.Drawing.Size(600, 22)
$progress.Style = 'Continuous'
$form.Controls.Add($progress)

$lblCurrent = New-Object System.Windows.Forms.Label
$lblCurrent.Text = ''
$lblCurrent.Location = New-Object System.Drawing.Point(12, 152)
$lblCurrent.Size = New-Object System.Drawing.Size(600, 20)
$lblCurrent.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblCurrent)

$lblFolders = New-Object System.Windows.Forms.Label
$lblFolders.Text = 'Synced folders:'
$lblFolders.Location = New-Object System.Drawing.Point(12, 180)
$lblFolders.Size = New-Object System.Drawing.Size(200, 18)
$lblFolders.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblFolders)

$lstFolders = New-Object System.Windows.Forms.ListBox
$lstFolders.Location = New-Object System.Drawing.Point(12, 200)
$lstFolders.Size = New-Object System.Drawing.Size(600, 68)
$lstFolders.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($lstFolders)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ScrollBars = 'Vertical'
$log.ReadOnly = $true
$log.Location = New-Object System.Drawing.Point(12, 278)
$log.Size = New-Object System.Drawing.Size(600, 152)
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$log.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($log)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = 'Restore backup...'
$btnRestore.Location = New-Object System.Drawing.Point(12, 440)
$btnRestore.Size = New-Object System.Drawing.Size(140, 32)
$form.Controls.Add($btnRestore)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = 'Update'
$btnUpdate.Location = New-Object System.Drawing.Point(432, 440)
$btnUpdate.Size = New-Object System.Drawing.Size(85, 32)
$form.Controls.Add($btnUpdate)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(527, 440)
$btnClose.Size = New-Object System.Drawing.Size(85, 32)
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

function Write-Log { param($m) $log.AppendText("$m`r`n"); [System.Windows.Forms.Application]::DoEvents() }
function Set-Status { param($m) $lblStatus.Text = $m; [System.Windows.Forms.Application]::DoEvents() }
function Set-Current { param($m) $lblCurrent.Text = $m; [System.Windows.Forms.Application]::DoEvents() }

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select your Minecraft version folder (usually .minecraft\versions\GG)'
    if ($script:VersionDir) { $dlg.SelectedPath = $script:VersionDir }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:VersionDir = $dlg.SelectedPath
        $txtPath.Text = $script:VersionDir
        Save-Config $script:VersionDir
    }
})

$btnUpdate.Add_Click({
    $btnUpdate.Enabled = $false
    $btnClose.Enabled = $false
    $btnBrowse.Enabled = $false
    $log.Clear()
    $progress.Value = 0
    Set-Current ''

    try {
        if (-not (Test-Path $script:VersionDir)) {
            Set-Status 'Error: version folder not set. Click Browse.'
            return
        }
        $modsDir = Resolve-ModsDir $script:VersionDir
        if (-not $modsDir) {
            Set-Status "Error: no 'mods' subfolder inside version folder."
            return
        }
        if (Test-MinecraftRunning) {
            Set-Status 'Error: Minecraft is running. Close the game first.'
            [System.Windows.Forms.MessageBox]::Show(
                'Minecraft appears to be running. Close the game and try again.',
                'Game running',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }

        $ignore = Load-IgnoreList
        if ($ignore.Count -gt 0) { Write-Log "Ignore patterns: $($ignore.Count) loaded from ignore.txt" }

        Set-Status 'Fetching manifest...'
        Write-Log "Version folder: $script:VersionDir"
        Write-Log "Mods folder:    $modsDir"
        Write-Log "Manifest:       $ManifestUrl"
        $ProgressPreference = 'SilentlyContinue'
        $manifest = Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing

        $wanted = @{}
        foreach ($m in $manifest.mods) { $wanted[$m.filename] = $m }

        $current = Get-ChildItem -Path $modsDir -Filter *.jar -File
        $currentMap = @{}
        foreach ($f in $current) { $currentMap[$f.Name] = $f }

        $toDeleteAll = @($current | Where-Object { -not $wanted.ContainsKey($_.Name) })
        $toDelete    = @($toDeleteAll | Where-Object { -not (Test-Ignored $_.Name $ignore) })
        $ignored     = @($toDeleteAll | Where-Object { Test-Ignored $_.Name $ignore })

        $toDownload = @()
        foreach ($m in $manifest.mods) {
            if (-not $currentMap.ContainsKey($m.filename)) {
                $toDownload += $m
            } elseif ($m.size -and $currentMap[$m.filename].Length -ne [long]$m.size) {
                $toDownload += $m
            }
        }

        # Folder sync planning
        $state = Load-SyncState $script:VersionDir
        $folderWork = @()
        $lstFolders.Items.Clear()
        if ($manifest.syncedFolders) {
            foreach ($entry in $manifest.syncedFolders) {
                $localSize = $null
                if ($state.PSObject.Properties[$entry.name]) { $localSize = [long]$state.($entry.name) }
                $sizeMb = [math]::Round($entry.size / 1MB, 2)
                if ($localSize -eq [long]$entry.size) {
                    [void]$lstFolders.Items.Add(("{0,-12} up to date ({1} MB)" -f $entry.name, $sizeMb))
                } else {
                    $folderWork += $entry
                    $label = if ($null -eq $localSize) { 'not synced yet' } else { 'needs update' }
                    [void]$lstFolders.Items.Add(("{0,-12} {1} ({2} MB)" -f $entry.name, $label, $sizeMb))
                }
            }
        }
        if ($lstFolders.Items.Count -eq 0) {
            [void]$lstFolders.Items.Add('(no folders in manifest)')
        }

        Write-Log "Manifest version: $($manifest.version)"
        Write-Log "Mods in manifest: $($manifest.mods.Count)"
        Write-Log "To delete:        $($toDelete.Count)"
        Write-Log "To download:      $($toDownload.Count)"
        Write-Log "Ignored (kept):   $($ignored.Count)"
        Write-Log "Folders to sync:  $($folderWork.Count)"
        Write-Log ''

        if ($toDelete.Count -eq 0 -and $toDownload.Count -eq 0 -and $folderWork.Count -eq 0) {
            Set-Status 'Already up to date.'
            $progress.Value = 100
            return
        }

        # Backup mods folder before any change
        if ($toDelete.Count -gt 0 -or $toDownload.Count -gt 0) {
            Set-Status 'Creating mods backup...'
            $backupPath = New-Backup -sourceDir $modsDir -versionDir $script:VersionDir -label 'mods'
            if ($backupPath) { Write-Log "Backup: $backupPath" }
        }

        foreach ($f in $toDelete) {
            Write-Log "- $($f.Name)"
            Remove-Item $f.FullName -Force
        }
        foreach ($f in $ignored) { Write-Log "= (ignored) $($f.Name)" }

        $total = $toDownload.Count + $folderWork.Count
        $i = 0

        foreach ($m in $toDownload) {
            $i++
            $dest = Join-Path $modsDir $m.filename
            $sizeMb = if ($m.size) { [math]::Round($m.size / 1MB, 1) } else { '?' }
            Set-Status "Downloading mod $i of $total..."
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

        # Folder sync
        foreach ($entry in $folderWork) {
            $i++
            $folderPath = Join-Path $script:VersionDir $entry.name
            $sizeMb = [math]::Round($entry.size / 1MB, 2)
            Set-Status "Syncing folder $($entry.name)..."
            Set-Current "[$i/$total] folder: $($entry.name) ($sizeMb MB)"
            Write-Log "* folder: $($entry.name)"

            # Backup existing folder
            if (Test-Path $folderPath) {
                $bp = New-Backup -sourceDir $folderPath -versionDir $script:VersionDir -label $entry.name
                if ($bp) { Write-Log "  backup: $bp" }
            }

            # Download zip
            $tempZip = Join-Path $env:TEMP ("gg-sync-" + $entry.name + ".zip")
            try {
                Invoke-WebRequest -Uri $entry.url -OutFile $tempZip -UseBasicParsing
                # Wipe existing folder
                if (Test-Path $folderPath) { Remove-Item -Path $folderPath -Recurse -Force }
                New-Item -ItemType Directory -Path $folderPath | Out-Null
                Expand-Archive -Path $tempZip -DestinationPath $folderPath -Force
                Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
                # Update state
                $state | Add-Member -NotePropertyName $entry.name -NotePropertyValue ([long]$entry.size) -Force
                Save-SyncState $script:VersionDir $state
                Write-Log "  ok"
                $sizeMbDone = [math]::Round($entry.size / 1MB, 2)
                for ($idx = 0; $idx -lt $lstFolders.Items.Count; $idx++) {
                    if ($lstFolders.Items[$idx].ToString().StartsWith($entry.name)) {
                        $lstFolders.Items[$idx] = ("{0,-12} up to date ({1} MB)" -f $entry.name, $sizeMbDone)
                        break
                    }
                }
            } catch {
                Write-Log "  ERROR: $($_.Exception.Message)"
                if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
            }
            $progress.Value = [int](($i / $total) * 100)
            [System.Windows.Forms.Application]::DoEvents()
        }

        Set-Current ''
        Set-Status "Done. $total item(s) updated."
    } catch {
        Set-Status "Error: $($_.Exception.Message)"
        Write-Log $_.Exception.Message
    } finally {
        $btnUpdate.Enabled = $true
        $btnClose.Enabled = $true
        $btnBrowse.Enabled = $true
    }
})

$btnRestore.Add_Click({
    if (-not (Test-Path $script:VersionDir)) {
        [System.Windows.Forms.MessageBox]::Show('Pick a version folder first.', 'Restore', 'OK', 'Information') | Out-Null
        return
    }
    $backupDir = Join-Path $script:VersionDir 'backups'
    if (-not (Test-Path $backupDir)) {
        [System.Windows.Forms.MessageBox]::Show('No backups yet.', 'Restore', 'OK', 'Information') | Out-Null
        return
    }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Pick a backup to restore'
    $dlg.InitialDirectory = $backupDir
    $dlg.Filter = 'Backup archives (*.zip)|*.zip'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    if (Test-MinecraftRunning) {
        [System.Windows.Forms.MessageBox]::Show('Close Minecraft first.', 'Game running', 'OK', 'Warning') | Out-Null
        return
    }

    $zipPath = $dlg.FileName
    $base = [System.IO.Path]::GetFileNameWithoutExtension($zipPath)
    $label = ($base -split '-')[0]
    $targetFolder = Join-Path $script:VersionDir $label

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Restore '$label' from:`n$zipPath`n`nTarget: $targetFolder`n`nThis will DELETE current '$label' folder contents.",
        'Confirm restore',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        $log.Clear()
        Write-Log "Restoring $label from $zipPath..."
        if (Test-Path $targetFolder) { Remove-Item -Path $targetFolder -Recurse -Force }
        New-Item -ItemType Directory -Path $targetFolder | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $targetFolder -Force
        # Invalidate sync state for that folder so next Update re-checks
        $state = Load-SyncState $script:VersionDir
        if ($state.PSObject.Properties[$label]) {
            $state.PSObject.Properties.Remove($label) | Out-Null
            Save-SyncState $script:VersionDir $state
        }
        Set-Status "Restored: $label"
        Write-Log 'Done.'
    } catch {
        Set-Status "Error: $($_.Exception.Message)"
        Write-Log $_.Exception.Message
    }
})

$lnkVersion.Add_LinkClicked({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Download latest update-gui.ps1 + update-gui.bat from GitHub and overwrite local copies?`n`nThe window will close after update -- relaunch manually.",
        'Self-update',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    try {
        $ProgressPreference = 'SilentlyContinue'
        $ps1 = Join-Path $PSScriptRoot 'update-gui.ps1'
        $bat = Join-Path $PSScriptRoot 'update-gui.bat'
        Invoke-WebRequest -Uri "$ScriptRawBase/update-gui.ps1" -OutFile $ps1 -UseBasicParsing
        Invoke-WebRequest -Uri "$ScriptRawBase/update-gui.bat" -OutFile $bat -UseBasicParsing
        [System.Windows.Forms.MessageBox]::Show('Scripts updated. Relaunch update-gui.bat.', 'Done', 'OK', 'Information') | Out-Null
        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Update failed: $($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
    }
})

$form.Add_Shown({
    $remote = Get-RemoteScriptVersion
    if ($remote -and $remote -ne $ScriptVersion) {
        $lnkVersion.Text = "v$ScriptVersion -> v$remote available (click to update)"
        $lnkVersion.LinkColor = [System.Drawing.Color]::ForestGreen
        $lnkVersion.Enabled = $true
    }
})

[void]$form.ShowDialog()
