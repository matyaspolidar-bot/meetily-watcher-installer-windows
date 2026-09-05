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
    # Cilime na 3.12, ne nejnovejsi verzi: ctranslate2==4.4.0 (tvrda zavislost
    # whisperx) nema wheel pro Python 3.13 (zjisteno na realnem Windows testu -
    # pip selhal na "Could not find a version that satisfies ctranslate2==4.4.0").
    # 'py' launcher misto bare 'python' - obchazi konflikt PATH, kdyby na
    # stroji uz byla nainstalovana i jina verze Pythonu.
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3.12 --version *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Python 3.12: uz nainstalovano"
            return
        }
    }
    Write-Info "Instaluji Python 3.12 pres winget..."
    winget install --id Python.Python.3.12 --source winget --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        Invoke-FailDialog "Instalace Pythonu pres winget selhala (kod $LASTEXITCODE)."
    }
    # winget po instalaci nerefreshne PATH v aktualnim procesu - dotahnout z registru.
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        Invoke-FailDialog "Python se nainstaloval, ale 'py' launcher neni videt v PATH v tomhle okne. Zavri Terminal/PowerShell, otevri znovu a spust install.ps1 znovu."
    }
    Write-Info "Python 3.12: hotovo"
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
    $venvOk = $false
    if (Test-Path $pythonExe) {
        & $pythonExe -c "import whisperx, faster_whisper" 2>$null
        $venvOk = ($LASTEXITCODE -eq 0)
    }
    if ($venvOk) {
        Write-Info "whisperx-env: uz existuje a funguje"
        return
    }
    New-Item -ItemType Directory -Force -Path $Script:WhisperSetupDir | Out-Null
    py -3.12 -m venv $Script:VenvDir
    if ($LASTEXITCODE -ne 0) {
        Invoke-FailDialog "Vytvoreni venv selhalo."
    }
    & $pythonExe -m pip install --quiet --upgrade pip whisperx pyannote-audio faster-whisper
    if ($LASTEXITCODE -ne 0) {
        Invoke-FailDialog "Instalace whisperx/pyannote-audio/faster-whisper selhala."
    }
    Write-Info "whisperx-env: hotovo"
}

function Stage-MeetilyApp {
    # ZATIM NEOVERENO na realnem stroji: presne umisteni/nazev nainstalovane
    # appky zavisi na tom, jak MSI instaluje (per-user vs per-machine). Marker
    # soubor misto kontroly Program Files, protoze tu cestu neznam predem.
    $marker = Join-Path $Script:WhisperSetupDir ".meetily-app-installed"
    if (Test-Path $marker) {
        Write-Info "Meetily.app: uz nainstalovano"
        return
    }
    # Tauri appky (jako Meetily) potrebuji Edge WebView2 Runtime - na cerstvem
    # Windows 10 nemusi byt predinstalovany (Windows 11 uz ho ma), a jeho
    # chybeni je castou pricinou obecne msiexec chyby 1603. Winget vrati
    # nenulovy kod, kdyz uz je nainstalovany - to je v poradku, ignorujeme.
    Write-Info "Kontroluji Edge WebView2 Runtime..."
    winget install --id Microsoft.EdgeWebView2Runtime --source winget --accept-package-agreements --accept-source-agreements --silent *> $null

    $msiUrl = "https://github.com/Zackriya-Solutions/meetily/releases/download/v0.4.0/meetily_0.4.0_x64_en-US.msi"
    $msiPath = Join-Path $env:TEMP "meetily_0.4.0_x64_en-US.msi"
    $msiLog = Join-Path $Script:WhisperSetupDir "meetily-msi-install.log"
    Write-Info "Stahuji instalator Meetily..."
    try {
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath
    } catch {
        Invoke-FailDialog "Stazeni instalatoru Meetily selhalo: $($_.Exception.Message)"
    }
    Write-Info "Instaluji Meetily (tise, bez oken)..."
    $proc = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Invoke-FailDialog "Instalace Meetily selhala (msiexec kod $($proc.ExitCode)). Podrobny log: $msiLog"
    }
    Remove-Item $msiPath -ErrorAction SilentlyContinue
    Set-Content -Path $marker -Value (Get-Date)
    Write-Info "Meetily.app: nainstalovano automaticky (v0.4.0)"
}

function Stage-CopyPayloadScripts {
    param([Parameter(Mandatory)][string]$PayloadDir)
    $files = @(
        "meetily_watcher.py", "meetily_autowatch.py", "export_transcript.py",
        "apply_speaker_names.py", "meetily_launch_prompt.py",
        "click_meetily_record.ps1", "transcribe_meeting.ps1"
    )
    foreach ($f in $files) {
        Copy-Item -Path (Join-Path $PayloadDir $f) -Destination $Script:WhisperSetupDir -Force
    }
    Write-Info "Watcher skripty: zkopirovano"
}

function Stage-ScheduledTasks {
    # Absolutni cesta ke konkretni verzi (3.12) pres 'py' launcher, ne bare
    # python.exe z PATH - stejny duvod jako u Stage-Venv, predvidatelnost bez
    # ohledu na to, jestli je na stroji jeste jina verze Pythonu.
    $python = (& py -3.12 -c "import sys; print(sys.executable)" 2>$null | Select-Object -Last 1).Trim()
    if (-not $python -or -not (Test-Path $python)) {
        Invoke-FailDialog "Nenasel jsem Python 3.12 pro registraci uloh na pozadi."
    }
    $pythonw = $python -replace "python\.exe$", "pythonw.exe"
    if (-not (Test-Path $pythonw)) { $pythonw = $python }

    $watcherScript = Join-Path $Script:WhisperSetupDir "meetily_autowatch.py"
    $promptScript = Join-Path $Script:WhisperSetupDir "meetily_launch_prompt.py"
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

    # Watcher - kontrola novych nahravek kazde 2 minuty (analogie StartInterval).
    Unregister-ScheduledTask -TaskName "MeetilyWatcher" -Confirm:$false -ErrorAction SilentlyContinue
    $watcherAction = New-ScheduledTaskAction -Execute $python -Argument "`"$watcherScript`""
    # [TimeSpan]::MaxValue (~10 milionu dni) se serializuje do Task Scheduler
    # XML jako P99999999DT23H59M59S, coz je mimo povoleny rozsah schematu
    # (overeno na realnem Windows - presne tahle hodnota v chybe). 10 let
    # je dost "navzdy" v praxi a bezpecne v rozsahu.
    $watcherTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration (New-TimeSpan -Days 3650)
    $watcherSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    Register-ScheduledTask -TaskName "MeetilyWatcher" -Action $watcherAction -Trigger $watcherTrigger `
        -Settings $watcherSettings -Principal $principal `
        -Description "Meetily Watcher - kontrola novych nahravek" | Out-Null
    Write-Info "Task Scheduler (MeetilyWatcher): nainstalovano a naplanovano"

    # Launch-prompt - bezi porad na pozadi, restartuje se pri padu (analogie KeepAlive).
    Unregister-ScheduledTask -TaskName "MeetilyLaunchPrompt" -Confirm:$false -ErrorAction SilentlyContinue
    $promptAction = New-ScheduledTaskAction -Execute $pythonw -Argument "`"$promptScript`""
    $promptTrigger = New-ScheduledTaskTrigger -AtLogOn
    $promptSettings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName "MeetilyLaunchPrompt" -Action $promptAction -Trigger $promptTrigger `
        -Settings $promptSettings -Principal $principal `
        -Description "Meetily Watcher - dialog Chcete zacit nahravat?" | Out-Null
    Start-ScheduledTask -TaskName "MeetilyLaunchPrompt"
    Write-Info "Task Scheduler (MeetilyLaunchPrompt): nainstalovano a spusteno"
}

function Test-Verify {
    # 30 pokusu/1s - poucka z Mac verze, kde 10s okno na overeni bezicniho
    # procesu hlasilo falesnou chybu, kdyz naskok trval o neco dele.
    $ok = $true
    $pythonExe = Join-Path $Script:VenvDir "Scripts\python.exe"
    & $pythonExe -c "import whisperx, faster_whisper" 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Warn "whisperx/faster-whisper se nedaji importovat"; $ok = $false }

    $watcherTask = Get-ScheduledTask -TaskName "MeetilyWatcher" -ErrorAction SilentlyContinue
    if (-not $watcherTask) { Write-Warn "uloha MeetilyWatcher neexistuje"; $ok = $false }

    $promptRunning = $false
    for ($i = 0; $i -lt 30; $i++) {
        $promptTask = Get-ScheduledTask -TaskName "MeetilyLaunchPrompt" -ErrorAction SilentlyContinue
        if ($promptTask -and $promptTask.State -eq "Running") { $promptRunning = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $promptRunning) { Write-Warn "hlidac dialogu pri zapnuti nebezi"; $ok = $false }

    return $ok
}
