Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$RepoSlug    = '1IDKey/GG'
$ReleaseTag  = 'v1.0.0'
$ModsDir     = Join-Path $env:APPDATA '.minecraft\versions\GG\mods'
$ManifestUrl = "https://raw.githubusercontent.com/$RepoSlug/main/manifest.json"
$LocalRepo   = $PSScriptRoot
$ManifestLocal = Join-Path $LocalRepo 'manifest.json'

function Get-GhPath {
    $cmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = 'C:\Program Files\GitHub CLI\gh.exe'
    if (Test-Path $fallback) { return $fallback }
    return $null
}

$GhPath = Get-GhPath

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GG Modpack Publisher'
$form.Size = New-Object System.Drawing.Size(820, 620)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = 'GG Modpack Publisher'
$lblHeader.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblHeader.Location = New-Object System.Drawing.Point(12, 12)
$lblHeader.Size = New-Object System.Drawing.Size(800, 28)
$form.Controls.Add($lblHeader)

$lblMeta = New-Object System.Windows.Forms.Label
$lblMeta.Text = "Repo: $RepoSlug   Tag: $ReleaseTag   Mods: $ModsDir"
$lblMeta.Location = New-Object System.Drawing.Point(12, 44)
$lblMeta.Size = New-Object System.Drawing.Size(800, 18)
$lblMeta.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblMeta)

function New-ListGroup {
    param($text, $x, $color)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text
    $lbl.Location = New-Object System.Drawing.Point($x, 72)
    $lbl.Size = New-Object System.Drawing.Size(260, 20)
    $lbl.ForeColor = $color
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($lbl)

    $lst = New-Object System.Windows.Forms.ListBox
    $lst.Location = New-Object System.Drawing.Point($x, 94)
    $lst.Size = New-Object System.Drawing.Size(260, 340)
    $lst.Font = New-Object System.Drawing.Font('Consolas', 9)
    $form.Controls.Add($lst)

    return @{ Label = $lbl; List = $lst }
}

$added   = New-ListGroup 'Added (upload)'     12  ([System.Drawing.Color]::ForestGreen)
$removed = New-ListGroup 'Removed (delete)'   284 ([System.Drawing.Color]::Firebrick)
$changed = New-ListGroup 'Changed (re-upload)' 556 ([System.Drawing.Color]::DarkGoldenrod)

$lblNotes = New-Object System.Windows.Forms.Label
$lblNotes.Text = 'Commit message:'
$lblNotes.Location = New-Object System.Drawing.Point(12, 446)
$lblNotes.Size = New-Object System.Drawing.Size(200, 18)
$form.Controls.Add($lblNotes)

$txtNotes = New-Object System.Windows.Forms.TextBox
$txtNotes.Location = New-Object System.Drawing.Point(12, 466)
$txtNotes.Size = New-Object System.Drawing.Size(540, 24)
$txtNotes.Text = 'Update modpack'
$form.Controls.Add($txtNotes)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ScrollBars = 'Vertical'
$log.ReadOnly = $true
$log.Location = New-Object System.Drawing.Point(12, 500)
$log.Size = New-Object System.Drawing.Size(540, 78)
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$log.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($log)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh diff'
$btnRefresh.Location = New-Object System.Drawing.Point(564, 466)
$btnRefresh.Size = New-Object System.Drawing.Size(120, 32)
$form.Controls.Add($btnRefresh)

$btnPublish = New-Object System.Windows.Forms.Button
$btnPublish.Text = 'Publish'
$btnPublish.Location = New-Object System.Drawing.Point(692, 466)
$btnPublish.Size = New-Object System.Drawing.Size(120, 32)
$btnPublish.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$btnPublish.Enabled = $false
$form.Controls.Add($btnPublish)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(692, 546)
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

$btnRefresh.Add_Click({
    $log.Clear()
    $added.List.Items.Clear()
    $removed.List.Items.Clear()
    $changed.List.Items.Clear()
    $btnPublish.Enabled = $false

    if (-not $GhPath) {
        Write-Log 'ERROR: gh CLI not found. Install GitHub CLI first.'
        return
    }
    if (-not (Test-Path $ModsDir)) {
        Write-Log "ERROR: mods folder not found: $ModsDir"
        return
    }

    Write-Log 'Loading local mods...'
    $local = Get-ChildItem -Path $ModsDir -Filter *.jar -File
    Write-Log "Local: $($local.Count) jars"

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
        & powershell -NoProfile -ExecutionPolicy Bypass -File $genScript -ModsDir $ModsDir -ReleaseTag $ReleaseTag -RepoSlug $RepoSlug -OutFile $ManifestLocal | Out-Null

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
    }
})

$form.Add_Shown({ $btnRefresh.PerformClick() })

[void]$form.ShowDialog()
