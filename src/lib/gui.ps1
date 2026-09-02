# Dialogy pro Windows - analogie lib/gui.sh (tam osascript, tady WinForms).
# Text bez diakritiky, viz poznámka v README.md (kódování .ps1 na PS 5.1).
Add-Type -AssemblyName System.Windows.Forms | Out-Null

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Warn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[VAROVANI] $Message"
}

function Show-WelcomeDialog {
    [System.Windows.Forms.MessageBox]::Show(
        "Vitej! Instalace potrva cca 30-60 minut (stahuji se AI modely, ~5-6GB).`n`n" +
        "Obcas se zepta na potvrzeni UAC okna a 3x otevre prohlizec (Hugging Face). " +
        "Nech to celou dobu bezet, i kdyz to bude chvili vypadat, ze se nic nedeje.",
        "Meetily Watcher - instalace",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Invoke-FailDialog {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ""
    Write-Host "X $Message"
    Write-Host "Log najdes v: $Global:InstallLog"
    [System.Windows.Forms.MessageBox]::Show(
        "X $Message`n`nNeco se nepovedlo. Posli prosim tenhle soubor Matyasovi:`n$Global:InstallLog",
        "Meetily Watcher - chyba",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

function Show-SuccessDialog {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ""
    Write-Host "OK $Message"
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        "Meetily Watcher",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}
