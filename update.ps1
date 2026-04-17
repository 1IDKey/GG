$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ManifestUrl = 'https://raw.githubusercontent.com/1IDKey/GG/main/manifest.json'
$ModsDir = Join-Path $env:APPDATA '.minecraft\versions\GG\mods'

function Write-Info    { param($m) Write-Host $m -ForegroundColor Cyan }
function Write-Ok      { param($m) Write-Host $m -ForegroundColor Green }
function Write-Warn    { param($m) Write-Host $m -ForegroundColor Yellow }
function Write-Err     { param($m) Write-Host $m -ForegroundColor Red }

Write-Info "=== GG Modpack Updater ==="
Write-Host "Папка модов: $ModsDir"

if (-not (Test-Path $ModsDir)) {
    Write-Err "Папка не найдена. Убедись, что установлена версия GG и игра запускалась хотя бы раз."
    exit 1
}

Write-Host "Загружаю манифест..."
try {
    $manifest = Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing
} catch {
    Write-Err "Не удалось скачать манифест: $($_.Exception.Message)"
    exit 1
}

Write-Host "Версия манифеста: $($manifest.version)"
Write-Host "Модов в манифесте: $($manifest.mods.Count)"
Write-Host ""

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

if ($toDelete.Count -eq 0 -and $toDownload.Count -eq 0) {
    Write-Ok "Всё актуально, обновлять нечего."
    exit 0
}

Write-Warn "Будет удалено:   $($toDelete.Count)"
Write-Warn "Будет скачано:   $($toDownload.Count)"
Write-Host ""

foreach ($f in $toDelete) {
    Write-Warn "- $($f.Name)"
    Remove-Item $f.FullName -Force
}

$i = 0
foreach ($m in $toDownload) {
    $i++
    $dest = Join-Path $ModsDir $m.filename
    $sizeMb = if ($m.size) { [math]::Round($m.size / 1MB, 1) } else { '?' }
    Write-Ok "[$i/$($toDownload.Count)] + $($m.filename) ($sizeMb MB)"
    try {
        Invoke-WebRequest -Uri $m.url -OutFile $dest -UseBasicParsing
    } catch {
        Write-Err "  Ошибка: $($_.Exception.Message)"
        if (Test-Path $dest) { Remove-Item $dest -Force }
    }
}

Write-Host ""
Write-Info "=== Готово ==="
