Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$RepoSlug    = '1IDKey/GG'
$ReleaseTag  = 'v1.0.0'
$ManifestUrl = "https://raw.githubusercontent.com/$RepoSlug/main/manifest.json"
$LocalRepo   = $PSScriptRoot
$ManifestLocal = Join-Path $LocalRepo 'manifest.json'
$ConfigFile    = Join-Path $PSScriptRoot 'gg-publisher.cfg'
$DefaultVersionDir = Join-Path $env:APPDATA '.minecraft\versions\GG'

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

$GhPath = Get-GhPath
$script:VersionDir = Load-Config

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GG Modpack Publisher'
$form.Size = New-Object System.Drawing.Size(1112, 680)
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
$lblMeta.Text = "Repo: $RepoSlug   Tag: $ReleaseTag"
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
    $lst.Size = New-Object System.Drawing.Size(260, 340)
    $lst.Font = New-Object System.Drawing.Font('Consolas', 9)
    $form.Controls.Add($lst)

    return @{ Label = $lbl; List = $lst }
}

$all     = New-ListGroup 'All mods (local)'   12   ([System.Drawing.Color]::SteelBlue)
$added   = New-ListGroup 'Added (upload)'     284  ([System.Drawing.Color]::ForestGreen)
$removed = New-ListGroup 'Removed (delete)'   556  ([System.Drawing.Color]::Firebrick)
$changed = New-ListGroup 'Changed (re-upload)' 828 ([System.Drawing.Color]::DarkGoldenrod)

$lblNotes = New-Object System.Windows.Forms.Label
$lblNotes.Text = 'Commit message:'
$lblNotes.Location = New-Object System.Drawing.Point(12, 500)
$lblNotes.Size = New-Object System.Drawing.Size(200, 18)
$form.Controls.Add($lblNotes)

$txtNotes = New-Object System.Windows.Forms.TextBox
$txtNotes.Location = New-Object System.Drawing.Point(12, 520)
$txtNotes.Size = New-Object System.Drawing.Size(812, 24)
$txtNotes.Text = 'Update modpack'
$form.Controls.Add($txtNotes)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ScrollBars = 'Vertical'
$log.ReadOnly = $true
$log.Location = New-Object System.Drawing.Point(12, 554)
$log.Size = New-Object System.Drawing.Size(812, 78)
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$log.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($log)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh diff'
$btnRefresh.Location = New-Object System.Drawing.Point(836, 520)
$btnRefresh.Size = New-Object System.Drawing.Size(120, 32)
$form.Controls.Add($btnRefresh)

$btnPublish = New-Object System.Windows.Forms.Button
$btnPublish.Text = 'Publish'
$btnPublish.Location = New-Object System.Drawing.Point(964, 520)
$btnPublish.Size = New-Object System.Drawing.Size(120, 32)
$btnPublish.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$btnPublish.Enabled = $false
$form.Controls.Add($btnPublish)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(964, 600)
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

function Format-Size {
    param([long]$bytes)
    if ($bytes -ge 1MB) { return ('{0:N1} MB' -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ('{0:N1} KB' -f ($bytes / 1KB)) }
    return "$bytes B"
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
    $btnPublish.Enabled = $false

    if (-not $GhPath) {
        Write-Log 'ERROR: gh CLI not found. Install GitHub CLI first.'
        return
    }
    $modsDir = Resolve-ModsDir $script:VersionDir
    if (-not $modsDir) {
        Write-Log 'ERROR: version folder not set. Click Browse.'
        return
    }

    Write-Log "Mods folder: $modsDir"
    Write-Log 'Loading local mods...'
    $local = Get-ChildItem -Path $modsDir -Filter *.jar -File | Sort-Object Name
    Write-Log "Local: $($local.Count) jars"

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

    $addedList   = @()
    $removedList = @()
    $changedList = @()

    foreach ($name in $localMap.Keys) {
        if (-not $remoteMap.ContainsKey($name)) {
            $addedList += $name
        } elseif ([long]$remoteMap[$name].size -ne $localMap[$name].Length) {
            $changedList += $name
        }
    }
    foreach ($name in $remoteMap.Keys) {
        if (-not $localMap.ContainsKey($name)) {
            $removedList += $name
        }
    }

    foreach ($n in ($addedList   | Sort-Object)) { [void]$added.List.Items.Add($n) }
    foreach ($n in ($removedList | Sort-Object)) { [void]$removed.List.Items.Add($n) }
    foreach ($n in ($changedList | Sort-Object)) { [void]$changed.List.Items.Add($n) }

    $added.Label.Text   = "Added (upload)     $($addedList.Count)"
    $removed.Label.Text = "Removed (delete)   $($removedList.Count)"
    $changed.Label.Text = "Changed (re-upload) $($changedList.Count)"

    $script:diff = @{
        Added    = $addedList
        Removed  = $removedList
        Changed  = $changedList
        LocalMap = $localMap
        ModsDir  = $modsDir
    }

    $hasWork = ($addedList.Count + $removedList.Count + $changedList.Count) -gt 0
    $btnPublish.Enabled = $hasWork
    if (-not $hasWork) { Write-Log 'Nothing to publish.' } else { Write-Log 'Diff ready. Review, then Publish.' }
})

$btnPublish.Add_Click({
    if (-not $script:diff) { return }
    $totalOps = $script:diff.Added.Count + $script:diff.Removed.Count + $script:diff.Changed.Count
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Publish $totalOps change(s) to $RepoSlug@$ReleaseTag?",
        'Confirm publish',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $btnPublish.Enabled = $false
    $btnRefresh.Enabled = $false
    $btnClose.Enabled = $false
    $btnBrowse.Enabled = $false

    try {
        foreach ($name in $script:diff.Removed) {
            Write-Log "- delete asset: $name"
            $r = Invoke-Gh @('release','delete-asset',$ReleaseTag,$name,'--repo',$RepoSlug,'--yes')
            if (-not $r.Ok) { Write-Log "  WARN: $($r.Output)" }
        }

        $uploads = @($script:diff.Added) + @($script:diff.Changed)
        $i = 0
        foreach ($name in $uploads) {
            $i++
            $path = $script:diff.LocalMap[$name].FullName
            Write-Log "+ upload [$i/$($uploads.Count)]: $name"
            $r = Invoke-Gh @('release','upload',$ReleaseTag,$path,'--repo',$RepoSlug,'--clobber')
            if (-not $r.Ok) { Write-Log "  ERROR: $($r.Output)" }
        }

        Write-Log 'Regenerating manifest.json...'
        $genScript = Join-Path $PSScriptRoot 'build-manifest.ps1'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $genScript -ModsDir $script:diff.ModsDir -ReleaseTag $ReleaseTag -RepoSlug $RepoSlug -OutFile $ManifestLocal | Out-Null

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
        [System.Windows.Forms.MessageBox]::Show('Published successfully.','GG Publisher',
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
