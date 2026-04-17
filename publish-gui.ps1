Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$RepoSlug      = '1IDKey/GG'
$ReleaseTag    = 'v1.0.0'
$ManifestUrl   = "https://raw.githubusercontent.com/$RepoSlug/main/manifest.json"
$LocalRepo     = $PSScriptRoot
$ManifestLocal = Join-Path $LocalRepo 'manifest.json'
$ConfigFile    = Join-Path $PSScriptRoot 'gg-publisher.cfg'
$DefaultVersionDir = Join-Path $env:APPDATA '.minecraft\versions\GG'
$SyncFolders   = @('config', 'kubejs')  # Edit to add/remove synced folders
$SetupFiles    = @('GG.jar', 'GG.json', 'TLauncherAdditional.json', 'options.txt')  # Files at version root packed into setup.zip

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
    if (Test-Path $versionDir) { return $versionDir }
    return $null
}

function Get-GhPath {
    $cmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = 'C:\Program Files\GitHub CLI\gh.exe'
    if (Test-Path $fallback) { return $fallback }
    return $null
}

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

function Format-Size {
    param([long]$bytes)
    if ($bytes -ge 1MB) { return ('{0:N1} MB' -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ('{0:N1} KB' -f ($bytes / 1KB)) }
    return "$bytes B"
}

$GhPath = Get-GhPath
$script:VersionDir = Load-Config

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GG Modpack Publisher'
$form.Size = New-Object System.Drawing.Size(1112, 720)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = 'GG Modpack Publisher'
$lblHeader.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblHeader.Location = New-Object System.Drawing.Point(12, 12)
$lblHeader.Size = New-Object System.Drawing.Size(1080, 28)
$form.Controls.Add($lblHeader)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = 'Version folder:'
$lblPath.Location = New-Object System.Drawing.Point(12, 46)
$lblPath.Size = New-Object System.Drawing.Size(100, 18)
$form.Controls.Add($lblPath)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(12, 66)
$txtPath.Size = New-Object System.Drawing.Size(980, 24)
$txtPath.ReadOnly = $true
$txtPath.Text = $script:VersionDir
$form.Controls.Add($txtPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse...'
$btnBrowse.Location = New-Object System.Drawing.Point(997, 65)
$btnBrowse.Size = New-Object System.Drawing.Size(95, 26)
$form.Controls.Add($btnBrowse)

$lblMeta = New-Object System.Windows.Forms.Label
$lblMeta.Text = "Repo: $RepoSlug   Tag: $ReleaseTag   SyncFolders: $($SyncFolders -join ', ')"
$lblMeta.Location = New-Object System.Drawing.Point(12, 98)
$lblMeta.Size = New-Object System.Drawing.Size(1080, 18)
$lblMeta.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblMeta)

function New-ListGroup {
    param($text, $x, $color)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text
    $lbl.Location = New-Object System.Drawing.Point($x, 126)
    $lbl.Size = New-Object System.Drawing.Size(260, 20)
    $lbl.ForeColor = $color
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($lbl)

    $lst = New-Object System.Windows.Forms.ListBox
    $lst.Location = New-Object System.Drawing.Point($x, 148)
    $lst.Size = New-Object System.Drawing.Size(260, 300)
    $lst.Font = New-Object System.Drawing.Font('Consolas', 9)
    $form.Controls.Add($lst)

    return @{ Label = $lbl; List = $lst }
}

$all     = New-ListGroup 'All mods (local)'   12   ([System.Drawing.Color]::SteelBlue)
$added   = New-ListGroup 'Added (upload)'     284  ([System.Drawing.Color]::ForestGreen)
$removed = New-ListGroup 'Removed (delete)'   556  ([System.Drawing.Color]::Firebrick)
$changed = New-ListGroup 'Changed (re-upload)' 828 ([System.Drawing.Color]::DarkGoldenrod)

$lblFolders = New-Object System.Windows.Forms.Label
$lblFolders.Text = 'Synced folders:'
$lblFolders.Location = New-Object System.Drawing.Point(12, 458)
$lblFolders.Size = New-Object System.Drawing.Size(200, 18)
$lblFolders.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblFolders)

$lstFolders = New-Object System.Windows.Forms.ListBox
$lstFolders.Location = New-Object System.Drawing.Point(12, 478)
$lstFolders.Size = New-Object System.Drawing.Size(540, 80)
$lstFolders.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($lstFolders)

$lblNotes = New-Object System.Windows.Forms.Label
$lblNotes.Text = 'Commit message:'
$lblNotes.Location = New-Object System.Drawing.Point(12, 566)
$lblNotes.Size = New-Object System.Drawing.Size(200, 18)
$form.Controls.Add($lblNotes)

$txtNotes = New-Object System.Windows.Forms.TextBox
$txtNotes.Location = New-Object System.Drawing.Point(12, 586)
$txtNotes.Size = New-Object System.Drawing.Size(812, 24)
$txtNotes.Text = 'Update modpack'
$form.Controls.Add($txtNotes)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ScrollBars = 'Vertical'
$log.ReadOnly = $true
$log.Location = New-Object System.Drawing.Point(564, 478)
$log.Size = New-Object System.Drawing.Size(520, 80)
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$log.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($log)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh diff'
$btnRefresh.Location = New-Object System.Drawing.Point(836, 586)
$btnRefresh.Size = New-Object System.Drawing.Size(120, 32)
$form.Controls.Add($btnRefresh)

$btnPublish = New-Object System.Windows.Forms.Button
$btnPublish.Text = 'Publish'
$btnPublish.Location = New-Object System.Drawing.Point(964, 586)
$btnPublish.Size = New-Object System.Drawing.Size(120, 32)
$btnPublish.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$btnPublish.Enabled = $false
$form.Controls.Add($btnPublish)

$btnServer = New-Object System.Windows.Forms.Button
$btnServer.Text = 'Deploy server...'
$btnServer.Location = New-Object System.Drawing.Point(836, 634)
$btnServer.Size = New-Object System.Drawing.Size(120, 32)
$btnServer.Add_Click({
    $deployScript = Join-Path $PSScriptRoot 'server-deploy.ps1'
    if (Test-Path $deployScript) {
        Start-Process -FilePath 'powershell' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$deployScript)
    } else {
        [System.Windows.Forms.MessageBox]::Show('server-deploy.ps1 not found.', 'Deploy', 'OK', 'Error') | Out-Null
    }
})
$form.Controls.Add($btnServer)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(964, 634)
$btnClose.Size = New-Object System.Drawing.Size(120, 32)
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

function Write-Log { param($m) $log.AppendText("$m`r`n"); [System.Windows.Forms.Application]::DoEvents() }

$script:diff = $null

function Invoke-Gh {
    param([string[]]$Args)
    $out = & $GhPath @Args 2>&1
    return @{ Ok = ($LASTEXITCODE -eq 0); Output = ($out -join "`n") }
}

function New-FolderZip {
    param($folderPath, $destZip)
    if (Test-Path $destZip) { Remove-Item $destZip -Force }
    Compress-Archive -Path (Join-Path $folderPath '*') -DestinationPath $destZip -CompressionLevel Optimal -Force
}

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select your Minecraft version folder (usually .minecraft\versions\GG)'
    if ($script:VersionDir) { $dlg.SelectedPath = $script:VersionDir }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:VersionDir = $dlg.SelectedPath
        $txtPath.Text = $script:VersionDir
        Save-Config $script:VersionDir
        $btnRefresh.PerformClick()
    }
})

$btnRefresh.Add_Click({
    $log.Clear()
    $all.List.Items.Clear()
    $added.List.Items.Clear()
    $removed.List.Items.Clear()
    $changed.List.Items.Clear()
    $lstFolders.Items.Clear()
    $btnPublish.Enabled = $false

    if (-not $GhPath) {
        Write-Log 'ERROR: gh CLI not found.'
        return
    }
    $modsDir = Resolve-ModsDir $script:VersionDir
    if (-not $modsDir) {
        Write-Log 'ERROR: version folder not set. Click Browse.'
        return
    }

    Write-Log "Mods folder: $modsDir"
    $local = Get-ChildItem -Path $modsDir -Filter *.jar -File | Sort-Object Name
    foreach ($f in $local) {
        [void]$all.List.Items.Add(("{0}  [{1}]" -f $f.Name, (Format-Size $f.Length)))
    }
    $all.Label.Text = "All mods (local)   $($local.Count)"

    Write-Log 'Fetching published manifest...'
    try {
        $remote = Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing
    } catch {
        Write-Log "ERROR fetching manifest: $($_.Exception.Message)"
        return
    }
    Write-Log "Published: $($remote.mods.Count) mods (version $($remote.version))"

    $localMap = @{}
    foreach ($f in $local) { $localMap[$f.Name] = $f }
    $remoteMap = @{}
    foreach ($m in $remote.mods) { $remoteMap[$m.filename] = $m }

    $addedList = @(); $removedList = @(); $changedList = @()
    foreach ($name in $localMap.Keys) {
        if (-not $remoteMap.ContainsKey($name)) { $addedList += $name }
        elseif ([long]$remoteMap[$name].size -ne $localMap[$name].Length) { $changedList += $name }
    }
    foreach ($name in $remoteMap.Keys) {
        if (-not $localMap.ContainsKey($name)) { $removedList += $name }
    }

    foreach ($n in ($addedList   | Sort-Object)) { [void]$added.List.Items.Add($n) }
    foreach ($n in ($removedList | Sort-Object)) { [void]$removed.List.Items.Add($n) }
    foreach ($n in ($changedList | Sort-Object)) { [void]$changed.List.Items.Add($n) }

    $added.Label.Text   = "Added (upload)     $($addedList.Count)"
    $removed.Label.Text = "Removed (delete)   $($removedList.Count)"
    $changed.Label.Text = "Changed (re-upload) $($changedList.Count)"

    # Synced folders display (no zip compute here; Publish will do it)
    $remoteFolders = @{}
    if ($remote.syncedFolders) {
        foreach ($f in $remote.syncedFolders) { $remoteFolders[$f.name] = $f }
    }
    foreach ($fname in $SyncFolders) {
        $fpath = Join-Path $script:VersionDir $fname
        $hasLocal = Test-Path $fpath
        $remoteInfo = if ($remoteFolders.ContainsKey($fname)) { "published ($([math]::Round($remoteFolders[$fname].size/1MB,2)) MB)" } else { 'not published' }
        $localInfo = if ($hasLocal) {
            $files = (Get-ChildItem $fpath -Recurse -File -ErrorAction SilentlyContinue).Count
            "local ($files files)"
        } else { 'local (missing)' }
        [void]$lstFolders.Items.Add(("{0,-12} {1}  |  {2}" -f $fname, $localInfo, $remoteInfo))
    }

    $script:diff = @{
        Added    = $addedList
        Removed  = $removedList
        Changed  = $changedList
        LocalMap = $localMap
        ModsDir  = $modsDir
        RemoteFolders = $remoteFolders
        Remote   = $remote
    }

    $hasWork = ($addedList.Count + $removedList.Count + $changedList.Count) -gt 0
    # Always allow Publish (folders might need sync even if mods didn't change)
    $btnPublish.Enabled = $true
    Write-Log 'Diff ready. Publish will also zip+compare sync folders.'
})

$btnPublish.Add_Click({
    if (-not $script:diff) { return }
    $modsOps = $script:diff.Added.Count + $script:diff.Removed.Count + $script:diff.Changed.Count
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Publish $modsOps mod change(s) + zip/compare folders ($($SyncFolders -join ', '))?",
        'Confirm publish',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    if (Test-MinecraftRunning) {
        [System.Windows.Forms.MessageBox]::Show(
            'Minecraft is running. Close the game before publishing (to avoid zipping locked files).',
            'Game running',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $btnPublish.Enabled = $false
    $btnRefresh.Enabled = $false
    $btnClose.Enabled = $false
    $btnBrowse.Enabled = $false

    try {
        # Mods: delete removed
        foreach ($name in $script:diff.Removed) {
            Write-Log "- delete asset: $name"
            $r = Invoke-Gh @('release','delete-asset',$ReleaseTag,$name,'--repo',$RepoSlug,'--yes')
            if (-not $r.Ok) { Write-Log "  WARN: $($r.Output)" }
        }

        # Mods: upload added/changed
        $uploads = @($script:diff.Added) + @($script:diff.Changed)
        $i = 0
        foreach ($name in $uploads) {
            $i++
            $path = $script:diff.LocalMap[$name].FullName
            Write-Log "+ upload [$i/$($uploads.Count)]: $name"
            $r = Invoke-Gh @('release','upload',$ReleaseTag,$path,'--repo',$RepoSlug,'--clobber')
            if (-not $r.Ok) { Write-Log "  ERROR: $($r.Output)" }
        }

        # Folders: zip each, compare, upload if differ
        $newFolderEntries = @()
        foreach ($fname in $SyncFolders) {
            $fpath = Join-Path $script:VersionDir $fname
            if (-not (Test-Path $fpath)) {
                Write-Log "? skip folder (not found): $fname"
                continue
            }
            $anyFiles = @(Get-ChildItem -Path $fpath -Recurse -File -ErrorAction SilentlyContinue)
            if ($anyFiles.Count -eq 0) {
                Write-Log "  skip (empty): $fname"
                continue
            }
            $tempZip = Join-Path $env:TEMP ("gg-publish-" + $fname + ".zip")
            Write-Log "* zipping folder: $fname ($($anyFiles.Count) files)"
            try {
                New-FolderZip -folderPath $fpath -destZip $tempZip
            } catch {
                Write-Log "  ERROR zipping: $($_.Exception.Message)"
                continue
            }
            $zipSize = (Get-Item $tempZip).Length
            $assetName = "folder__$fname.zip"
            $remoteSize = if ($script:diff.RemoteFolders.ContainsKey($fname)) { [long]$script:diff.RemoteFolders[$fname].size } else { -1 }

            if ($zipSize -ne $remoteSize) {
                Write-Log ("  changed ({0} -> {1}), uploading..." -f (Format-Size ([long][math]::Max(0,$remoteSize))), (Format-Size $zipSize))
                $uploadSpec = "$tempZip#$assetName"
                $r = Invoke-Gh @('release','upload',$ReleaseTag,$uploadSpec,'--repo',$RepoSlug,'--clobber')
                if (-not $r.Ok) {
                    Write-Log "  ERROR: $($r.Output)"
                    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
                    continue
                }
            } else {
                Write-Log '  unchanged'
            }
            $url = "https://github.com/$RepoSlug/releases/download/$ReleaseTag/$assetName"
            $newFolderEntries += [ordered]@{ name = $fname; url = $url; size = $zipSize }
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        }

        # Build and upload setup bundle
        $setupEntry = $null
        $existingSetupFiles = @()
        $existingSetupNames = @()
        foreach ($sf in $SetupFiles) {
            $full = Join-Path $script:VersionDir $sf
            if (Test-Path $full) {
                $existingSetupFiles += $full
                $existingSetupNames += $sf
            } else {
                Write-Log "? setup: missing $sf"
            }
        }
        if ($existingSetupFiles.Count -gt 0) {
            $setupZip = Join-Path $env:TEMP 'gg-publish-setup.zip'
            if (Test-Path $setupZip) { Remove-Item $setupZip -Force }
            Write-Log "* zipping setup bundle ($($existingSetupFiles.Count) files)"
            try {
                Compress-Archive -Path $existingSetupFiles -DestinationPath $setupZip -CompressionLevel Optimal -Force
                $setupSize = (Get-Item $setupZip).Length
                $setupAsset = 'setup.zip'
                $remoteSetup = $null
                if ($script:diff.Remote -and $script:diff.Remote.setup -and $script:diff.Remote.setup.size) {
                    $remoteSetup = [long]$script:diff.Remote.setup.size
                }
                if ($setupSize -ne $remoteSetup) {
                    Write-Log ("  uploading setup ({0})" -f (Format-Size $setupSize))
                    $r = Invoke-Gh @('release','upload',$ReleaseTag,"$setupZip#$setupAsset",'--repo',$RepoSlug,'--clobber')
                    if (-not $r.Ok) { Write-Log "  ERROR: $($r.Output)" }
                } else {
                    Write-Log '  unchanged'
                }
                $setupEntry = [ordered]@{
                    url   = "https://github.com/$RepoSlug/releases/download/$ReleaseTag/$setupAsset"
                    size  = $setupSize
                    files = @($existingSetupNames)
                }
                Remove-Item $setupZip -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Log "  ERROR zipping setup: $($_.Exception.Message)"
            }
        }

        # Regenerate manifest (mods) and overlay new folder entries
        Write-Log 'Regenerating manifest.json...'
        $genScript = Join-Path $PSScriptRoot 'build-manifest.ps1'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $genScript -ModsDir $script:diff.ModsDir -ReleaseTag $ReleaseTag -RepoSlug $RepoSlug -OutFile $ManifestLocal | Out-Null

        # Write folder and setup entries into manifest
        $mf = Get-Content $ManifestLocal -Raw | ConvertFrom-Json
        $mf | Add-Member -NotePropertyName syncedFolders -NotePropertyValue (@($newFolderEntries)) -Force
        if ($setupEntry) {
            $mf | Add-Member -NotePropertyName setup -NotePropertyValue $setupEntry -Force
        } elseif ($script:diff.Remote -and $script:diff.Remote.setup) {
            $mf | Add-Member -NotePropertyName setup -NotePropertyValue $script:diff.Remote.setup -Force
        }
        ($mf | ConvertTo-Json -Depth 6) | Set-Content -Path $ManifestLocal -Encoding UTF8

        Write-Log 'git add/commit/push...'
        Push-Location $LocalRepo
        try {
            & git add manifest.json 2>&1 | Out-Null
            $msg = $txtNotes.Text
            if (-not $msg) { $msg = 'Update modpack' }
            & git commit -m $msg 2>&1 | ForEach-Object { Write-Log "  $_" }
            & git push 2>&1 | ForEach-Object { Write-Log "  $_" }
        } finally {
            Pop-Location
        }

        Write-Log 'Done.'
        [System.Windows.Forms.MessageBox]::Show('Published.', 'GG Publisher',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        $btnRefresh.PerformClick()
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
    } finally {
        $btnRefresh.Enabled = $true
        $btnClose.Enabled = $true
        $btnBrowse.Enabled = $true
    }
})

$form.Add_Shown({ $btnRefresh.PerformClick() })
[void]$form.ShowDialog()
