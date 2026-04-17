param(
    [string]$ModsDir    = (Join-Path $env:APPDATA '.minecraft\versions\GG\mods'),
    [string]$ReleaseTag = 'v1.0.0',
    [string]$RepoSlug   = '1IDKey/GG',
    [string]$Version    = '1.0.0',
    [string]$OutFile    = (Join-Path $PSScriptRoot 'manifest.json')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ModsDir)) {
    Write-Host "Mods folder not found: $ModsDir" -ForegroundColor Red
    exit 1
}

# Preserve syncedFolders and setup from existing manifest, since only publish-gui touches them
$existingFolders = @()
$existingSetup = $null
if (Test-Path $OutFile) {
    try {
        $existing = Get-Content $OutFile -Raw | ConvertFrom-Json
        if ($existing.syncedFolders) { $existingFolders = @($existing.syncedFolders) }
        if ($existing.setup) { $existingSetup = $existing.setup }
    } catch {}
}

$jars = Get-ChildItem -Path $ModsDir -Filter *.jar -File | Sort-Object Name

$mods = foreach ($j in $jars) {
    [ordered]@{
        filename = $j.Name
        url      = "https://github.com/$RepoSlug/releases/download/$ReleaseTag/$([uri]::EscapeDataString($j.Name))"
        size     = $j.Length
    }
}

$manifest = [ordered]@{
    version        = $Version
    mods           = @($mods)
    syncedFolders  = @($existingFolders)
}
if ($existingSetup) { $manifest.setup = $existingSetup }

$json = $manifest | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($OutFile, $json, [System.Text.UTF8Encoding]::new($false))

$totalMb = [math]::Round(($jars | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Host "Done: $($jars.Count) mods, $totalMb MB" -ForegroundColor Green
Write-Host "Preserved syncedFolders: $($existingFolders.Count)"
Write-Host "Manifest: $OutFile"
