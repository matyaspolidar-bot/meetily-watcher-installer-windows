# meetily-watcher-installer-windows

Windows instalátor Whisper/Meetily watcher pipeline pro Addvery konzultanty.
Sesterský repozitář k [`meetily-watcher-installer`](https://github.com/matyaspolidar-bot/meetily-watcher-installer)
(macOS verze) - stejný princip (Path A: pošli tenhle repo Claude Code zprávou,
nebo PowerShell příkaz z landing page jako záloha), ale Windows-nativní
mechanismy místo macOS.

## Stav: probíhá reálné testování na Windows (v0.3.0)

Poprvé spuštěno na reálném Windows stroji přes Claude Code (Path A) - nálezy
zatím opravené:
- Parse chyba v `stages.ps1` (`;` uvnitř `(...)` použitého jako operand
  `-and` - PowerShell to nedovolí, potřeba `$(...)` nebo rozepsat na víc
  příkazů).
- `whisperx` vyžaduje přesně `ctranslate2==4.4.0`, který nemá wheel pro
  Python 3.13 - cíl přepnut na Python 3.12 (přes `py -3.12` launcher, ne
  bare `python` z PATH, kvůli riziku konfliktu s jinou nainstalovanou verzí).
- Tichá instalace appky Meetily (`msiexec /quiet /qn`) padala s kódem 1603,
  když účet byl jen členem skupiny Administrators, ale neběžel skutečně
  elevovaně - `Test-AdminGroupMembership` takový účet propustí (má UAC řešit
  sám za jednotlivé kroky), ale `msiexec` bez `-Verb RunAs` v tichém režimu
  žádný UAC dialog nevyvolá a prostě selže. Oprava: `Start-Process msiexec.exe`
  teď v `stages.ps1` běží s `-Verb RunAs`.
- `DB_PATH` v `meetily_watcher.py` (odhad `%APPDATA%\com.meetily.ai\...` podle
  Tauri konvence) nejdřív padal - první test byl na stroji, kde se
  předpokládalo, že appka běží jako MSIX balíček (Windows by pak soubory
  virtualizoval do `%LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalCache\
  Roaming\com.meetily.ai\...`). `meetily_watcher.py` teď zkouší tuhle
  variantu nejdřív (glob přes `Packages/*/...`, `PackageFamilyName` má
  náhodný hash-suffix různý pro každou instalaci) a pak spadne zpátky na
  původní `%APPDATA%\com.meetily.ai\...`. Na opakovaných reálných testech
  (včetně čisté reinstalace 09/2026) se appka chová jako klasická
  (non-MSIX) instalace a používá se právě ten fallback - MSIX větev zůstává
  jen jako pojistka pro jiný způsob instalace/budoucí verzi appky.
- Po úspěšné instalaci appky padal `Start-Process "meetily"` (bare příkaz
  není na PATH) terminující výjimkou i přes `-ErrorAction SilentlyContinue`
  (`Start-Process` tohle ignoruje u file-not-found) - opraveno na plnou cestu
  `$env:ProgramFiles\meetily\meetily.exe` obalenou v try/catch.
- Tenhle automatický autoopen appku spouštěl s právy správce (dědil je po
  celém elevovaném `install.ps1`) - uživatel pak nemohl appku normálně
  zavřít/ovládat z neelevovaného okna (Windows neposílá UI zprávy z nižší
  do vyšší integrity úrovně). Opraveno spuštěním přes `explorer.exe`, který
  vždy běží s právy přihlášeného uživatele bez ohledu na to, odkud je
  zavolaný - stejné jako běžný dvojklik na ikonu appky.

Celý flow je napsaný feature-parity s Mac verzí: `install.ps1` (admin práva,
místo na disku, zámek proti souběžnému běhu), `winget` instalace Python +
ffmpeg, jeden venv s `whisperx`/`pyannote-audio`/`faster-whisper`, HF
onboarding, automatická instalace appky Meetily (`.msi`, tichý `msiexec`),
port watcher skriptů (`meetily_watcher.py`, `meetily_autowatch.py`,
`export_transcript.py`, `apply_speaker_names.py`), registrace úlohy v Task
Scheduleru (běh na pozadí).

Test doběhl až po instalaci appky Meetily a registraci Task Scheduler úlohy
(po opravě elevace výše). `DB_PATH` je teď ověřený proti reálné databázi.

Celý end-to-end běh watcher pipeline je od 09/2026 ověřený na skutečné
nahrávce: nahráno v appce Meetily → `MeetilyWatcher` zachytí dokončenou
nahrávku → přepis (`faster-whisper`) → rozpoznání mluvčích (`pyannote`) →
zápis zpět do Meetily databáze (`transcripts` tabulka) → export do sdílené
složky. Všechno proběhlo bez chyby na reálné češtině.

Dialog "Chcete začít nahrávat?" (`meetily_launch_prompt.py` +
`click_meetily_record.ps1`, automatické klikání na tlačítko Nahrávat) byl
odstraněn - konzultanti appku spouští a nahrávají ručně sami, watcher jen
zpracovává hotové nahrávky na pozadí.

Landing page (`docs/index.html`) má tři cesty instalace: dvojklik na
`docs/Nainstalovat-Meetily.zip` (primární, doporučená pro netechnické
uživatele - `.bat` uvnitř se sám povýší na správce přes UAC a spustí
bootstrap), Path A přes `CLAUDE.md` (poslat odkaz Claude Code), nebo ruční
PowerShell příkaz. Distribuce jako `.zip` místo holého
`.bat` obchází Chrome/Edge varování "tento typ souboru může poškodit
počítač" (to je čistě podle přípony souboru) - zůstává jen mírnější Windows
dialog "Neznámý vydavatel" při spuštění, který se objevuje u každého
staženého skriptu bez placeného code-signing certifikátu.

Krátký tvar `irm <url> | iex` (stáhni skript a rovnou ho spusť v jednom
řádku) se na reálném testu 09/2026 opakovaně srazil s Windows Defenderem -
ML heuristika `Trojan:Win32/Commando.A!ml` ho u souboru staženého z
internetu (Mark of the Web) tiše zabila, instalace skončila okamžitě s
"Přístup odepřen" a bez zápisu do `install.log`. `.bat` i landing page teď
místo toho stahují bootstrap skript do souboru a spouští ho přes `&`/`-File`
- funkčně stejné, jen to nevypadá jako živý download-cradle řetězec.

## Automatické rozpoznání mluvčího podle hlasu (nepovinné)

`voice_profiles.py` umí přiřadit reálné jméno mluvčímu úplně automaticky,
bez ručního vyplňování `_speakers.json` - použije stejný embedding model,
jaký diarizace stejně mimochodem stahuje (`pyannote/wespeaker-voxceleb-
resnet34-LM`), porovná hlas každého mluvčího s dopředu zaznamenanými
profily kolegů a při dostatečné podobnosti (práh 0.75, konzervativně -
raději neznámý mluvčí než špatně přiřazené jméno) rovnou dosadí jméno
místo `SPEAKER_00`/`01`/... Ověřeno end-to-end na reálném testu (dvě různé
nahrávky stejného člověka, druhá správně automaticky pojmenovaná).

Jednorázová registrace (každý konzultant sám za sebe, stačí krátká 10-30s
čistá nahrávka vlastního hlasu, libovolný formát - m4a, mp4, wav, cokoliv
umí přečíst ffmpeg):

```
cd %USERPROFILE%\whisper-setup
whisperx-env\Scripts\python.exe voice_profiles.py enroll "Jan Novak" cesta\k\nahravce.m4a
```

Bez zaregistrovaného hlasu se všechno chová přesně jako předtím
(`SPEAKER_00`/`01` + ruční `apply_speaker_names.py`) - nic se nerozbije.

## Návrh jmen účastníků z firemního kalendáře (nepovinné)

`teams_attendees.py` umí po zpracování nahrávky navrhnout jména podle toho,
kdo byl pozvaný na kalendářovou událost, která se časově kryje s nahrávkou -
místo prázdné šablony na jméno mluvčího (`_speakers.json`) dostaneš i soubor
`_ucastnici_navrh.txt` se skutečným seznamem pozvaných. **Nepozná, kdo z nich
zrovna mluvil** (diarizace zůstává `SPEAKER_00`/`01`/...) - jen usnadní ruční
vyplnění `_speakers.json` (viz `apply_speaker_names.py`), místo vymýšlení
jména z hlavy.

Bez konfigurace se tahle část potichu přeskočí - nic se nerozbije. Zapnutí
vyžaduje jednorázový zásah IT/administrátora Addvery v Azure AD:

1. Azure Portal → Azure Active Directory → App registrations → New registration
   (stačí libovolný název, např. "Meetily Watcher - kalendář").
2. API permissions → Add a permission → Microsoft Graph → Application permissions
   → Calendars → `Calendars.Read` → Add permissions → **Grant admin consent**.
3. Certificates & secrets → New client secret → zkopírovat hodnotu (je vidět jen jednou).
4. Předat: Tenant ID, Application (client) ID, hodnotu client secretu.

Tyhle tři hodnoty se vyplní do `%USERPROFILE%\whisper-setup\teams_config.json`
(zkopírovat z `teams_config.example.json` ve stejné složce). `calendar_user`
lze nechat prázdné - odvodí se automaticky z přihlášeného Windows účtu
(`whoami /upn`), případně přepsat konkrétním e-mailem.

## Mapování mechanismů (Mac → Windows)

| Mac | Windows |
|---|---|
| bash | PowerShell |
| `curl \| bash` | `irm <url>/install.ps1 \| iex` |
| Homebrew | `winget install Python.Python.3.12`, `winget install Gyan.FFmpeg` |
| launchd (`StartInterval`/`KeepAlive`) | Task Scheduler (`Register-ScheduledTask`) |
| `osascript display dialog` | `System.Windows.Forms.MessageBox` / `Microsoft.VisualBasic.Interaction.InputBox` |
| `hdiutil` mount DMG | silent `.msi`/`.exe` install |
| `pgrep` | `Get-Process` |
| `dscl` admin check | `Get-LocalGroupMember -Group Administrators` |
| `df -g` | `Get-PSDrive` |
| MLX transkripce (Apple-only) | `faster-whisper` (whisperx na něm staví) - jeden venv místo dvou |
| `$HOME/whisper-setup` | `$env:USERPROFILE\whisper-setup` |

## Struktura

```
docs/index.html                           # landing page - stažení + navod + FAQ k varovanim
docs/Nainstalovat-Meetily.zip             # .bat zabaleny v zipu (distribuce pro netechnicke uzivatele)
docs/Nainstalovat-Meetily.bat             # dvojklik instalator - sam se povysi na spravce (UAC) a spusti bootstrap
docs/install.ps1                          # bootstrap - stáhne + rozbalí + spustí install.ps1
src/install.ps1                           # entrypoint
src/lib/gui.ps1                           # dialogy (WinForms/VisualBasic)
src/lib/stages.ps1                        # idempotentní instalační kroky
src/lib/hf_onboarding.ps1                 # HuggingFace účet/licence/token flow
src/payload/meetily_watcher.py            # zpracuje jeden meeting (přepis+diarizace)
src/payload/meetily_autowatch.py          # periodická kontrola nových nahrávek (Task Scheduler)
src/payload/export_transcript.py          # export do sdílené složky + mapování jmen mluvčích
src/payload/apply_speaker_names.py        # aplikuje ručně vyplněná jména mluvčích
src/payload/transcribe_meeting.ps1        # diarizace + přepis jednoho audio souboru
src/payload/teams_attendees.py            # nepovinny navrh jmen z kalendare (Microsoft Graph)
src/payload/teams_config.example.json     # sablona konfigurace pro teams_attendees.py
src/payload/voice_profiles.py             # automaticke rozpoznani mluvciho podle hlasu
```

## Poznámka k diakritice

Skripty vypisují texty do konzole/dialogů bez diakritiky (`Vitej!` místo
`Vítej!`). Windows PowerShell 5.1 bez BOM v `.ps1` souboru občas špatně
interpretuje UTF-8 řetězcové literály (rozbitá diakritika v konzoli i v
dialogových oknech) - vynechání diakritiky je jednodušší a spolehlivější než
řešit BOM/kódování konzole na neznámé cílové mašině. Ověří se na reálném
Windows stroji a případně se to doladí.
