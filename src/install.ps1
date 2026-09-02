# Meetily Watcher (Windows) - konsolidovany instalator.
# Analogie install.sh - spousti se z docs/install.ps1 (irm | iex).
$ErrorActionPreference = "Stop"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Global:WhisperSetupDir = Join-Path $env:USERPROFILE "whisper-setup"
$Global:InstallLog = Join-Path $Global:WhisperSetupDir "install.log"

New-Item -ItemType Directory -Force -Path $Global:WhisperSetupDir | Out-Null
Start-Transcript -Path $Global:InstallLog -Append -IncludeInvocationHeader | Out-Null

Write-Host "=== Meetily Watcher instalace: $(Get-Date) ==="
Write-Host "(Vidis tady bezet text - to je normalni prubeh instalace, nech to bezet.)"

. (Join-Path $ScriptDir "lib\gui.ps1")
. (Join-Path $ScriptDir "lib\stages.ps1")
. (Join-Path $ScriptDir "lib\hf_onboarding.ps1")

trap {
    Invoke-FailDialog "Instalace selhala: $($_.Exception.Message)"
}

Enter-InstallLock
try {
    Show-WelcomeDialog

    Test-AdminGroupMembership
    Test-DiskSpace -MinGb 10

    Stage-Winget
    Stage-Python
    Stage-Ffmpeg
    Stage-Venv

    Stage-HfOnboarding

    # TODO (dalsi faze): instalace appky Meetily (.msi/.exe), Task Scheduler
    # ulohy pro watcher/launch-prompt, port watcher skriptu, UI Automation
    # klik na "Nahravat". Zatim konci tady - viz README.md "Stav: ve vyvoji".

    Show-SuccessDialog "Kostra instalace hotova (Python, ffmpeg, whisperx-env, HF token). Dalsi casti (appka Meetily, watcher na pozadi) jeste nejsou hotove - viz README.md."
}
finally {
    Exit-InstallLock
    Stop-Transcript | Out-Null
}
