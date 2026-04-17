$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dst = Join-Path $src 'dist\client'

$files = @(
    @{ From = 'update-gui.bat';     To = 'update-gui.bat' },
    @{ From = 'update-gui.ps1';     To = 'update-gui.ps1' },
    @{ From = 'ignore.example.txt'; To = 'ignore.example.txt' },
    @{ From = 'readme-player.txt';  To = 'README.txt' }
)

if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }

foreach ($f in $files) {
    $from = Join-Path $src $f.From
    $to   = Join-Path $dst $f.To
    Copy-Item -Path $from -Destination $to -Force
    Write-Host "copied: $($f.From) -> $($f.To)"
}

# Build zip alongside
$zip = Join-Path $src 'dist\gg-client.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $dst '*') -DestinationPath $zip -CompressionLevel Optimal -Force
$zipSize = [math]::Round((Get-Item $zip).Length / 1KB, 1)
Write-Host ""
Write-Host "Client folder: $dst"
Write-Host "Zip:           $zip ($zipSize KB)"
