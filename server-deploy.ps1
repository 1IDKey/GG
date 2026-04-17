Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ScriptVersion       = '1.0.0'
$ConfigFile          = Join-Path $PSScriptRoot 'gg-server.cfg'
$VersionConfigFile   = Join-Path $PSScriptRoot 'gg-publisher.cfg'
$BlacklistFile       = Join-Path $PSScriptRoot 'server-mods-blacklist.txt'
$BlacklistExample    = Join-Path $PSScriptRoot 'server-mods-blacklist.example.txt'
$DefaultVersionDir   = Join-Path $env:APPDATA '.minecraft\versions\GG'

$DefaultServerConfig = @{
    host       = 'flux.bisquit.host'
    port       = 2022
    user       = 'jqb6h3dm.8696ab23'
    modsPath   = '/mods'
    panelBase  = 'https://mgr.bisquit.host'
    serverId   = '8696ab23'
    apiKey     = ''
}

function Load-ServerConfig {
    if (Test-Path $ConfigFile) {
        try { return Get-Content $ConfigFile -Raw | ConvertFrom-Json } catch {}
    }
    $cfg = New-Object PSObject
    foreach ($k in $DefaultServerConfig.Keys) { $cfg | Add-Member -NotePropertyName $k -NotePropertyValue $DefaultServerConfig[$k] }
    return $cfg
}

function Save-ServerConfig { param($cfg) ($cfg | ConvertTo-Json) | Set-Content -Path $ConfigFile -Encoding UTF8 }

function Load-VersionDir {
    if (Test-Path $VersionConfigFile) {
        $p = (Get-Content $VersionConfigFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($p -and (Test-Path $p)) { return $p }
    }
    if (Test-Path $DefaultVersionDir) { return $DefaultVersionDir }
    return ''
}

function Load-Blacklist {
    $path = $null
    if (Test-Path $BlacklistFile) { $path = $BlacklistFile }
    elseif (Test-Path $BlacklistExample) { $path = $BlacklistExample }
    if (-not $path) { return @() }
    return @(Get-Content $path | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
}

function Test-Blacklisted {
    param($name, $patterns)
    foreach ($p in $patterns) { if ($name -like $p) { return $true } }
    return $false
}

function Invoke-SftpBatch {
    param($cfg, [string[]]$commands)
    $batch = [System.IO.Path]::GetTempFileName()
    try {
        $commands | Set-Content -Path $batch -Encoding ASCII
        $target = "$($cfg.user)@$($cfg.host)"
        $out = & sftp -o BatchMode=yes -o StrictHostKeyChecking=no -P $cfg.port -b $batch $target 2>&1
        return @{ Ok = ($LASTEXITCODE -eq 0); Output = ($out -join "`n"); Lines = $out }
    } finally {
        Remove-Item $batch -Force -ErrorAction SilentlyContinue
    }
}

function Get-ServerMods {
    param($cfg)
    $r = Invoke-SftpBatch $cfg @("cd $($cfg.modsPath)", "ls -1")
    if (-not $r.Ok) { return $null }
    $jars = @()
    foreach ($ln in $r.Lines) {
        $s = ($ln -as [string]).Trim()
        if ($s -match '\.jar$') { $jars += $s }
    }
    return $jars
}

function Get-JHash { param([int]$b)
    $x = 123456789; $k = 0
    for ($i = 0; $i -lt 1677696; $i++) {
        $x = (($x + $b) -bxor ($x + ($x % 3) + ($x % 17) + $b) -bxor $i) % 16776960
        if (($x % 117) -eq 0) { $k = ($k + 1) % 1111 }
    }
    return $k
}

function New-PterodactylSession {
    param($cfg)
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    $uri = [uri]"$($cfg.panelBase)/api/client"
    # Probe to obtain __js_p_ cookie via raw HttpWebRequest (more reliable than Invoke-WebRequest)
    $req = [System.Net.HttpWebRequest]::CreateHttp($uri)
    $req.UserAgent = $ua
    $req.Method = 'GET'
    $req.AllowAutoRedirect = $false
    $req.Timeout = 15000
    $req.CookieContainer = New-Object System.Net.CookieContainer
    try {
        $resp = $req.GetResponse()
        $resp.Close()
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) { $_.Exception.Response.Close() }
    }
    $cookies = $req.CookieContainer.GetCookies($uri)
    $jsCookie = $null
    foreach ($c in $cookies) { if ($c.Name -eq '__js_p_') { $jsCookie = $c; break } }
    if (-not $jsCookie) { throw "StormWall __js_p_ cookie not received. Panel blocked or auth issue." }
    $code = [int](($jsCookie.Value -split ',')[0])
    $jhash = Get-JHash $code
    $hostName = $uri.Host
    $container = New-Object System.Net.CookieContainer
    $container.Add($uri, (New-Object System.Net.Cookie('__js_p_', $jsCookie.Value, '/', $hostName)))
    $container.Add($uri, (New-Object System.Net.Cookie('__jhash_', "$jhash", '/', $hostName)))
    $container.Add($uri, (New-Object System.Net.Cookie('__jua_', [uri]::EscapeDataString($ua), '/', $hostName)))
    return @{ Cookies = $container; UA = $ua; Code = $code; JHash = $jhash }
}

function Invoke-PterodactylApi {
    param($cfg, $session, $path, $method = 'GET', $body = $null)
    $uri = [uri]"$($cfg.panelBase)$path"
    $req = [System.Net.HttpWebRequest]::CreateHttp($uri)
    $req.Method = $method
    $req.UserAgent = $session.UA
    $req.Accept = 'application/json'
    $req.Headers.Add('Authorization', "Bearer $($cfg.apiKey)")
    $req.CookieContainer = $session.Cookies
    $req.AllowAutoRedirect = $false
    $req.Timeout = 30000
    if ($body) {
        $req.ContentType = 'application/json'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $req.ContentLength = $bytes.Length
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
    }
    try {
        $resp = $req.GetResponse()
        $status = [int]$resp.StatusCode
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $content = $reader.ReadToEnd()
        $reader.Close()
        $resp.Close()
        return @{ StatusCode = $status; Content = $content }
    } catch [System.Net.WebException] {
        $eresp = $_.Exception.Response
        if ($eresp) {
            $status = [int]$eresp.StatusCode
            $reader = New-Object System.IO.StreamReader($eresp.GetResponseStream())
            $content = $reader.ReadToEnd()
            $reader.Close()
            $eresp.Close()
            return @{ StatusCode = $status; Content = $content }
        }
        throw
    }
}

function Send-ServerPower {
    param($cfg, $signal = 'restart')
    $session = New-PterodactylSession $cfg
    $path = "/api/client/servers/$($cfg.serverId)/power"
    $body = (@{ signal = $signal } | ConvertTo-Json -Compress)
    $resp = Invoke-PterodactylApi -cfg $cfg -session $session -path $path -method 'POST' -body $body
    return $resp.StatusCode
}

$script:Config     = Load-ServerConfig
$script:VersionDir = Load-VersionDir
$script:Diff       = $null

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GG Server Deploy'
$form.Size = New-Object System.Drawing.Size(860, 680)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = 'GG Server Deploy'
$lblHeader.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblHeader.Location = New-Object System.Drawing.Point(12, 12)
$lblHeader.Size = New-Object System.Drawing.Size(600, 28)
$form.Controls.Add($lblHeader)

$lblVer = New-Object System.Windows.Forms.Label
$lblVer.Text = "v$ScriptVersion"
$lblVer.Location = New-Object System.Drawing.Point(700, 18)
$lblVer.Size = New-Object System.Drawing.Size(130, 20)
$lblVer.TextAlign = 'MiddleRight'
$lblVer.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblVer)

$lblHost = New-Object System.Windows.Forms.Label
$lblHost.Text = 'SFTP target:'
$lblHost.Location = New-Object System.Drawing.Point(12, 50)
$lblHost.Size = New-Object System.Drawing.Size(100, 18)
$form.Controls.Add($lblHost)

$txtTarget = New-Object System.Windows.Forms.TextBox
$txtTarget.Location = New-Object System.Drawing.Point(12, 70)
$txtTarget.Size = New-Object System.Drawing.Size(700, 24)
$txtTarget.ReadOnly = $true
$txtTarget.Text = "$($script:Config.user)@$($script:Config.host):$($script:Config.port) -> $($script:Config.modsPath)"
$form.Controls.Add($txtTarget)

$btnEdit = New-Object System.Windows.Forms.Button
$btnEdit.Text = 'Edit...'
$btnEdit.Location = New-Object System.Drawing.Point(717, 69)
$btnEdit.Size = New-Object System.Drawing.Size(120, 26)
$form.Controls.Add($btnEdit)

$lblVerDir = New-Object System.Windows.Forms.Label
$lblVerDir.Text = "Local mods source: $($script:VersionDir)\mods"
$lblVerDir.Location = New-Object System.Drawing.Point(12, 102)
$lblVerDir.Size = New-Object System.Drawing.Size(820, 18)
$lblVerDir.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblVerDir)

$lblBl = New-Object System.Windows.Forms.Label
$lblBl.Text = 'Blacklist: (loading)'
$lblBl.Location = New-Object System.Drawing.Point(12, 122)
$lblBl.Size = New-Object System.Drawing.Size(820, 18)
$lblBl.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblBl)

function New-ListGroup {
    param($text, $x, $color)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text
    $lbl.Location = New-Object System.Drawing.Point($x, 150)
    $lbl.Size = New-Object System.Drawing.Size(260, 20)
    $lbl.ForeColor = $color
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($lbl)

    $lst = New-Object System.Windows.Forms.ListBox
    $lst.Location = New-Object System.Drawing.Point($x, 172)
    $lst.Size = New-Object System.Drawing.Size(260, 280)
    $lst.Font = New-Object System.Drawing.Font('Consolas', 9)
    $form.Controls.Add($lst)

    return @{ Label = $lbl; List = $lst }
}

$shouldHave  = New-ListGroup 'Should be on server' 12  ([System.Drawing.Color]::SteelBlue)
$toUpload    = New-ListGroup 'To upload (missing)' 284 ([System.Drawing.Color]::ForestGreen)
$toDelete    = New-ListGroup 'To delete (extra)'   556 ([System.Drawing.Color]::Firebrick)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ScrollBars = 'Vertical'
$log.ReadOnly = $true
$log.Location = New-Object System.Drawing.Point(12, 464)
$log.Size = New-Object System.Drawing.Size(700, 120)
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$log.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($log)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh diff'
$btnRefresh.Location = New-Object System.Drawing.Point(717, 464)
$btnRefresh.Size = New-Object System.Drawing.Size(120, 32)
$form.Controls.Add($btnRefresh)

$btnDeploy = New-Object System.Windows.Forms.Button
$btnDeploy.Text = 'Deploy'
$btnDeploy.Location = New-Object System.Drawing.Point(717, 504)
$btnDeploy.Size = New-Object System.Drawing.Size(120, 32)
$btnDeploy.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$btnDeploy.Enabled = $false
$form.Controls.Add($btnDeploy)

$chkRestart = New-Object System.Windows.Forms.CheckBox
$chkRestart.Text = 'Restart server after deploy (via API)'
$chkRestart.Location = New-Object System.Drawing.Point(12, 593)
$chkRestart.Size = New-Object System.Drawing.Size(400, 24)
$chkRestart.Checked = $true
$form.Controls.Add($chkRestart)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(717, 552)
$btnClose.Size = New-Object System.Drawing.Size(120, 32)
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

$btnRestartOnly = New-Object System.Windows.Forms.Button
$btnRestartOnly.Text = 'Restart only'
$btnRestartOnly.Location = New-Object System.Drawing.Point(420, 590)
$btnRestartOnly.Size = New-Object System.Drawing.Size(120, 28)
$form.Controls.Add($btnRestartOnly)

function Write-Log { param($m) $log.AppendText("$m`r`n"); [System.Windows.Forms.Application]::DoEvents() }

$btnEdit.Add_Click({
    $prompt = @"
host=$($script:Config.host)
port=$($script:Config.port)
user=$($script:Config.user)
modsPath=$($script:Config.modsPath)
"@
    $input = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Edit server config (key=value per line):",
        'Server config',
        $prompt)
    if (-not $input) { return }
    foreach ($ln in ($input -split "`r?`n")) {
        if ($ln -match '^(\w+)\s*=\s*(.+)$') {
            $script:Config | Add-Member -NotePropertyName $matches[1] -NotePropertyValue $matches[2].Trim() -Force
        }
    }
    if ($script:Config.port -is [string]) { $script:Config.port = [int]$script:Config.port }
    Save-ServerConfig $script:Config
    $txtTarget.Text = "$($script:Config.user)@$($script:Config.host):$($script:Config.port) -> $($script:Config.modsPath)"
    Write-Log 'Config saved.'
})

[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')

$btnRefresh.Add_Click({
    $log.Clear()
    $shouldHave.List.Items.Clear()
    $toUpload.List.Items.Clear()
    $toDelete.List.Items.Clear()
    $btnDeploy.Enabled = $false

    $blacklist = Load-Blacklist
    $lblBl.Text = "Blacklist: $($blacklist.Count) patterns"
    Write-Log "Blacklist: $($blacklist.Count) patterns"

    $modsDir = Join-Path $script:VersionDir 'mods'
    if (-not (Test-Path $modsDir)) {
        Write-Log "ERROR: local mods folder not found: $modsDir"
        return
    }

    $localJars = @(Get-ChildItem -Path $modsDir -Filter *.jar -File | ForEach-Object { $_.Name } | Sort-Object)
    $wanted = @($localJars | Where-Object { -not (Test-Blacklisted $_ $blacklist) })
    $skipped = @($localJars | Where-Object { Test-Blacklisted $_ $blacklist })

    Write-Log "Local: $($localJars.Count) jars. Server-eligible: $($wanted.Count). Skipped by blacklist: $($skipped.Count)."

    foreach ($n in $wanted) { [void]$shouldHave.List.Items.Add($n) }
    $shouldHave.Label.Text = "Should be on server   $($wanted.Count)"

    Write-Log "Fetching server mods (sftp)..."
    $serverJars = Get-ServerMods $script:Config
    if ($null -eq $serverJars) {
        Write-Log 'ERROR: SFTP connect/list failed. Check SSH key + config.'
        return
    }
    Write-Log "Server: $($serverJars.Count) jars"

    $wantedSet = @{}
    foreach ($n in $wanted) { $wantedSet[$n] = $true }
    $serverSet = @{}
    foreach ($n in $serverJars) { $serverSet[$n] = $true }

    $uploadList = @($wanted | Where-Object { -not $serverSet.ContainsKey($_) })
    $deleteList = @($serverJars | Where-Object { -not $wantedSet.ContainsKey($_) })

    foreach ($n in $uploadList) { [void]$toUpload.List.Items.Add($n) }
    foreach ($n in $deleteList) { [void]$toDelete.List.Items.Add($n) }

    $toUpload.Label.Text = "To upload (missing)   $($uploadList.Count)"
    $toDelete.Label.Text = "To delete (extra)     $($deleteList.Count)"

    $script:Diff = @{
        ModsDir = $modsDir
        Upload  = $uploadList
        Delete  = $deleteList
    }

    $hasWork = ($uploadList.Count + $deleteList.Count) -gt 0
    $btnDeploy.Enabled = $hasWork
    if (-not $hasWork) { Write-Log 'Server is in sync. Nothing to deploy.' } else { Write-Log 'Diff ready. Review, then Deploy.' }
})

$btnDeploy.Add_Click({
    if (-not $script:Diff) { return }
    $totalOps = $script:Diff.Upload.Count + $script:Diff.Delete.Count
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Deploy $totalOps change(s) to server?`n  Upload: $($script:Diff.Upload.Count)`n  Delete: $($script:Diff.Delete.Count)",
        'Confirm deploy',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $btnDeploy.Enabled = $false
    $btnRefresh.Enabled = $false
    $btnClose.Enabled = $false
    $btnEdit.Enabled = $false

    try {
        # Delete pass
        if ($script:Diff.Delete.Count -gt 0) {
            Write-Log "Deleting $($script:Diff.Delete.Count) file(s)..."
            $cmds = @("cd $($script:Config.modsPath)")
            foreach ($n in $script:Diff.Delete) {
                $cmds += "rm `"$n`""
                Write-Log "- $n"
            }
            $r = Invoke-SftpBatch $script:Config $cmds
            if (-not $r.Ok) { Write-Log "Delete errors: $($r.Output)" }
        }

        # Upload pass (one file per batch to get per-file progress)
        if ($script:Diff.Upload.Count -gt 0) {
            Write-Log "Uploading $($script:Diff.Upload.Count) file(s)..."
            $i = 0
            foreach ($n in $script:Diff.Upload) {
                $i++
                $localPath = Join-Path $script:Diff.ModsDir $n
                Write-Log "+ [$i/$($script:Diff.Upload.Count)] $n"
                $remoteQuoted = "`"$($script:Config.modsPath)/$n`""
                $localQuoted = "`"$localPath`""
                $r = Invoke-SftpBatch $script:Config @("put $localQuoted $remoteQuoted")
                if (-not $r.Ok) { Write-Log "  ERROR: $($r.Output)" }
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        Write-Log 'Deploy done.'

        if ($chkRestart.Checked -and $script:Config.apiKey) {
            Write-Log 'Restarting server via API (solving StormWall challenge, ~5s)...'
            try {
                $code = Send-ServerPower $script:Config 'restart'
                if ($code -eq 204) { Write-Log 'Restart signal sent (204).' }
                else { Write-Log "Unexpected status: $code" }
            } catch {
                Write-Log "Restart failed: $($_.Exception.Message)"
            }
        } elseif ($chkRestart.Checked) {
            Write-Log 'Skipping restart: apiKey not set in gg-server.cfg.'
        }

        [System.Windows.Forms.MessageBox]::Show(
            'Done.',
            'Deployed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        $btnRefresh.PerformClick()
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
    } finally {
        $btnRefresh.Enabled = $true
        $btnClose.Enabled = $true
        $btnEdit.Enabled = $true
    }
})

$btnRestartOnly.Add_Click({
    if (-not $script:Config.apiKey) {
        Write-Log 'ERROR: apiKey not set in gg-server.cfg.'
        return
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        'Send restart signal to the server now?',
        'Restart',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $btnRestartOnly.Enabled = $false
    try {
        Write-Log 'Solving StormWall challenge...'
        $code = Send-ServerPower $script:Config 'restart'
        if ($code -eq 204) { Write-Log 'Restart sent.' } else { Write-Log "Status: $code" }
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
    } finally {
        $btnRestartOnly.Enabled = $true
    }
})

$form.Add_Shown({ $btnRefresh.PerformClick() })
[void]$form.ShowDialog()
