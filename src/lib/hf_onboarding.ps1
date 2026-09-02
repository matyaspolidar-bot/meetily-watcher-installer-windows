# HuggingFace ucet/licence/token flow - analogie lib/hf_onboarding.sh.
Add-Type -AssemblyName Microsoft.VisualBasic | Out-Null

$Script:HfGatedModels = @(
    "pyannote/speaker-diarization-3.1",
    "pyannote/segmentation-3.0",
    "pyannote/speaker-diarization-community-1"
)

function Show-OkDialog {
    param([Parameter(Mandatory)][string]$Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message, "Meetily Watcher",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Stage-HfOnboarding {
    $tokenFile = Join-Path $env:USERPROFILE ".cache\huggingface\token"
    if ((Test-Path $tokenFile) -and (Get-Content $tokenFile -ErrorAction SilentlyContinue)) {
        Write-Info "HuggingFace token: uz nastaveno"
        return
    }

    Show-OkDialog @"
Ted potrebujeme pristup k Hugging Face - bezplatne sluzbe, ktera hostuje AI model pro rozpoznavani mluvcich. Bude to trvat cca 5 minut, 4 kroky.

Za chvili se otevre stranka:
huggingface.co/join

Pokud tam jeste nemas ucet: vypln e-mail, uzivatelske jmeno a heslo, klikni na zelene tlacitko 'Create Account', a potvrd ucet klikem na odkaz, ktery ti prijde e-mailem.

Pokud ucet uz mas, jen se prihlas (tlacitko 'Log In' vpravo nahore) a klikni Pokracovat.
"@
    Start-Process "https://huggingface.co/join"
    Show-OkDialog "Pokracuj, az budes mit ucet zalozeny/prihlaseny (potvrzeny e-mail, pokud jsi ho zakladal/a ted poprve)."

    $modelCount = $Script:HfGatedModels.Count
    for ($i = 0; $i -lt $modelCount; $i++) {
        $model = $Script:HfGatedModels[$i]
        Start-Process "https://huggingface.co/$model"
        Show-OkDialog @"
Krok $($i + 1) ze ${modelCount}: otevrela se stranka modelu

huggingface.co/$model

Sjed na tehle strance dolu, uvidis formular 'You need to agree to share your contact information'. Vypln ho (staci zaskrtnout souhlas, pokud tam je) a klikni na zelene tlacitko s textem 'Agree and access repository'.

Az se ti pod tim tlacitkem objevi zelena fajfka / potvrzeni pristupu, klikni tady na OK.
"@
    }

    Start-Process "https://huggingface.co/settings/tokens/new"
    Show-OkDialog @"
Posledni krok - vytvoreni tokenu (hesla pro appku k Hugging Face). Otevrela se stranka:

huggingface.co/settings/tokens/new

Udelej presne tohle:
1. Do pole 'Name' napis cokoliv, treba 'meetily'.
2. U 'Token type' vyber moznost 'Read' (ne 'Write' ani 'Fine-grained').
3. Klikni na modre tlacitko 'Create token' dole.
4. Objevi se okno s tokenem (dlouhy text zacinajici 'hf_...'). Klikni na ikonku kopirovani vedle nej (nebo ho oznac a Ctrl+C).

Token si NIKAM neuklade ani nikomu neposilej - hned po zkopirovani klikni OK a vloz ho v dalsim okne.
"@

    $token = [Microsoft.VisualBasic.Interaction]::InputBox("Vloz zkopirovany token (Ctrl+V) - musi zacinat hf_:", "Meetily Watcher", "")

    if ($token -notmatch "^hf_") {
        Invoke-FailDialog "Token nevypada platne - mel by zacinat 'hf_' a nic vic. Zkontroluj, ze jsi zkopiroval/a cely token (huggingface.co/settings/tokens), a spust appku znovu."
    }

    $hfCli = Join-Path $Script:VenvDir "Scripts\huggingface-cli.exe"
    & $hfCli login --token $token
    if ($LASTEXITCODE -ne 0) {
        Invoke-FailDialog "Prihlaseni k Hugging Face selhalo - zkontroluj internetove pripojeni a spust appku znovu."
    }
    Write-Info "HuggingFace token: nastaveno"
}
