# Idempotentni instalacni kroky - analogie lib/stages.sh.
# Kazda Stage-* funkce nejdriv zkontroluje, jestli uz je splnena, a pokud ano,
# vrati se hned - bezpecne znovuspusteni cele install.ps1 po jakekoliv chybe.

$Script:WhisperSetupDir = Join-Path $env:USERPROFILE "whisper-setup"
$Script:VenvDir = Join-Path $Script:WhisperSetupDir "whisperx-env"

function Test-AdminGroupMembership {
    # Analogie dscl . -read /Groups/admin GroupMembership - kontroluje clenstvi
    # ve skupine Administrators, ne jestli tenhle proces bezi elevovane (to
    # jednotlive kroky nize reseni pres UAC prompt samy, kdyz je potreba).
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Info "Admin prava: OK (bezi elevovane)"
        return
    }
    try {
        $members = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
        $isMember = $members | Where-Object { $_.Name -eq $currentUser.Name -or $_.SID -eq $currentUser.User }
        if ($isMember) {
            Write-Info "Admin prava: OK (clen skupiny Administrators)"
            return
        }
    } catch {
        Write-Warn "Nepodarilo se overit clenstvi ve skupine Administrators ($($_.Exception.Message)) - pokracuji, jednotlive kroky si UAC vyzadaji same."
        return
    }
    Invoke-FailDialog "Tenhle ucet nema na tomhle PC prava spravce. Instalace vyzaduje moznost potvrdit UAC dialogy (instalace Pythonu/appky). Kontaktuj IT nebo Matyase, at ti prava spravce prideli, a pak zkus instalaci znovu."
}

function Test-DiskSpace {
    param([int]$MinGb = 10)
    $drive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(":"))
    $availableGb = [math]::Round($drive.Free / 1GB)
    if ($availableGb -lt $MinGb) {
        Invoke-FailDialog "Na disku je jen ${availableGb}GB volneho mista, instalace potrebuje aspon ${MinGb}GB (modely pro rozpoznavani reci). Uvolni misto a zkus to znovu."
    }
    Write-Info "Volne misto na disku: ${availableGb}GB - OK"
}

function Enter-InstallLock {
    # mkdir je atomicky i na Windows - stejny princip jako zamek v Mac install.sh.
    $lockDir = Join-Path $Script:WhisperSetupDir ".install.lock"
    $Script:LockDir = $lockDir
    try {
        New-Item -ItemType Directory -Path $lockDir -ErrorAction Stop | Out-Null
    } catch {
        $pidFile = Join-Path $lockDir "pid"
        $otherPid = if (Test-Path $pidFile) { Get-Content $pidFile -ErrorAction SilentlyContinue } else { $null }
        if ($otherPid -and (Get-Process -Id $otherPid -ErrorAction SilentlyContinue)) {
            Write-Host "Instalace uz bezi v jinem okne (PID $otherPid) - pockej, az dobehne, a zkus to pak znovu."
            exit 1
        }
        Write-Host "Nalezen zamek po predchozim nedokoncenem behu (proces uz nebezi) - prebiram ho."
        Remove-Item -Recurse -Force $lockDir -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $lockDir | Out-Null
    }
    Set-Content -Path (Join-Path $lockDir "pid") -Value $PID
}

function Exit-InstallLock {
    if ($Script:LockDir -and (Test-Path $Script:LockDir)) {
        Remove-Item -Recurse -Force $Script:LockDir -ErrorAction SilentlyContinue
    }
}

function Stage-Winget {
    # Zkontroluje, ze winget vubec existuje (Windows 10 1709+/Windows 11 ho ma
    # predinstalovany; starsi Windows 10 buildy ne - tam by fail_dialog odkazal
    # na rucni instalaci App Installeru z Microsoft Store).
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Invoke-FailDialog "Chybi 'winget' (App Installer). Nainstaluj ho z Microsoft Store (vyhledej 'App Installer') a zkus to znovu."
    }
    Write-Info "winget: OK"
}

function Stage-Python {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $version = (& python --version 2>&1).ToString()
        if ($version -match "3\.1[3-9]") {
            Write-Info "Python ($version): uz nainstalovano"
            return
        }
    }
    Write-Info "Instaluji Python 3.13 pres winget..."
    winget install --id Python.Python.3.13 --source winget --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        Invoke-FailDialog "Instalace Pythonu pres winget selhala (kod $LASTEXITCODE)."
    }
    # winget po instalaci nerefreshne PATH v aktualnim procesu - dotahnout z registru.
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Invoke-FailDialog "Python se nainstaloval, ale neni videt v PATH v tomhle okne. Zavri Terminal/PowerShell, otevri znovu a spust install.ps1 znovu."
    }
    Write-Info "Python 3.13: hotovo"
}

function Stage-Ffmpeg {
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
        Write-Info "ffmpeg: uz nainstalovano"
        return
    }
    Write-Info "Instaluji ffmpeg pres winget..."
    winget install --id Gyan.FFmpeg --source winget --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        Invoke-FailDialog "Instalace ffmpeg pres winget selhala (kod $LASTEXITCODE)."
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        Invoke-FailDialog "ffmpeg se nainstaloval, ale neni videt v PATH v tomhle okne. Zavri Terminal/PowerShell, otevri znovu a spust install.ps1 znovu."
    }
    Write-Info "ffmpeg: hotovo"
}

function Stage-Venv {
    # Na rozdil od Macu (mlx-env + whisperx-env zvlast kvuli rychlosti MLX na
    # Apple Silicon) staci na Windows JEDEN venv - faster-whisper (na kterem
    # whisperx uz interne stavi) zvladne transkripci i diarizaci spolu.
    $pythonExe = Join-Path $Script:VenvDir "Scripts\python.exe"
    if ((Test-Path $pythonExe) -and (& $pythonExe -c "import whisperx, faster_whisper" 2>$null; $LASTEXITCODE -eq 0)) {
        Write-Info "whisperx-env: uz existuje a funguje"
        return
    }
    New-Item -ItemType Directory -Force -Path $Script:WhisperSetupDir | Out-Null
    python -m venv $Script:VenvDir
    if ($LASTEXITCODE -ne 0) {
        Invoke-FailDialog "Vytvoreni venv selhalo."
    }
    & $pythonExe -m pip install --quiet --upgrade pip whisperx pyannote-audio faster-whisper
    if ($LASTEXITCODE -ne 0) {
        Invoke-FailDialog "Instalace whisperx/pyannote-audio/faster-whisper selhala."
    }
    Write-Info "whisperx-env: hotovo"
}
