# Meetily Watcher (Windows) - bootstrap instalator.
# Analogie docs/install.sh: stahne repo (zatim jako zip primo z branche main -
# az bude hotova appka/Task Scheduler faze, muze se to prehodit na pinned
# GitHub Release jako u Mac verze), rozbali, spusti src/install.ps1.
$ErrorActionPreference = "Stop"

$RepoZipUrl = "https://github.com/matyaspolidar-bot/meetily-watcher-installer-windows/archive/refs/heads/main.zip"

$TmpDir = Join-Path $env:TEMP ("meetily-watcher-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

Write-Host ""
Write-Host "== Meetily Watcher (Windows) - instalace =="
Write-Host ""
Write-Host "Tohle je normalni PowerShell okno, ne chyba. Uvidis tady postupne vypisovat"
Write-Host "text - to je prubeh instalace, nech to bezet."
Write-Host ""
Write-Host "-> Stahuji instalator..."

$zipPath = Join-Path $TmpDir "payload.zip"
try {
    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zipPath
} catch {
    Write-Host ""
    Write-Host "Stazeni se nepovedlo. Zkontroluj pripojeni k internetu a zkus to znovu."
    Write-Host "Pokud problem pretrva, napis Matyasovi."
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "-> Rozbaluji..."
Expand-Archive -Path $zipPath -DestinationPath $TmpDir -Force

$extractedDir = Get-ChildItem -Path $TmpDir -Directory |
    Where-Object { $_.Name -like "meetily-watcher-installer-windows-*" } |
    Select-Object -First 1

if (-not $extractedDir) {
    Write-Host "Rozbaleni se nepovedlo (nenasel jsem ocekavanou slozku). Napis Matyasovi."
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "-> Spoustim instalaci (trva 30-60 minut, nezavirej tohle okno)..."
Write-Host ""

& (Join-Path $extractedDir.FullName "src\install.ps1")
$exitCode = $LASTEXITCODE

Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
exit $exitCode
