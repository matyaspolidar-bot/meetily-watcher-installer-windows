# Meetily Watcher (Windows) - konsolidovany instalator.
# Analogie install.sh - spousti se z docs/install.ps1 (irm | iex).
$ErrorActionPreference = "Stop"
# PowerShell 7.3+ jinak automaticky hodi terminujici chybu pri nenulovem exit
# kodu externiho prikazu (py/winget/pip/...) - cely skript ale pocita s
# klasickym chovanim (kontrola $LASTEXITCODE rucne). Bez tohohle by kazde
# ocekavane "zkontroluj a pripadne nainstaluj" selhalo hned na prvnim testu.
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}
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

    Stage-MeetilyApp
    Stage-CopyPayloadScripts -PayloadDir (Join-Path $ScriptDir "payload")
    Stage-ScheduledTasks

    if (Test-Verify) {
        Show-SuccessDialog "Hotovo! Meetily Watcher je nainstalovany a bezi na pozadi."
        [System.Windows.Forms.MessageBox]::Show(
            "Posledni krok, neda se odklikat automaticky - Windows se te muze sam zeptat na povoleni Mikrofon / Nahravani obrazovky, kdyz appku poprve pouzijes.`n`nKlikni vzdy Povolit, jinak appka nebude fungovat. Otevri ted Meetily a zkus to.",
            "Meetily Watcher - posledni krok",
            [System.Windows.Forms.MessageBoxButtons]::OK
        ) | Out-Null
        Start-Process "meetily" -ErrorAction SilentlyContinue
    } else {
        Invoke-FailDialog "Instalace dobehla, ale kontrola na konci nasla problem - podivej se vys do logu."
    }
}
finally {
    Exit-InstallLock
    Stop-Transcript | Out-Null
}
