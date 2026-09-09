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
  Tauri konvence) byl špatně - appka je nainstalovaná jako MSIX balíček, takže
  Windows její soubory virtualizuje do
  `%LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalCache\Roaming\com.meetily.ai\...`.
  `PackageFamilyName` má náhodný hash-suffix různý pro každou instalaci, takže
  `meetily_watcher.py` teď cestu hledá dynamicky (glob přes `Packages/*/...`)
  místo hardcodované hodnoty; MeetilyWatcher scheduled task kvůli tomu padal
  na každém běhu (`sqlite3.OperationalError: unable to open database file`).
- Po úspěšné instalaci appky padal `Start-Process "meetily"` (bare příkaz
  není na PATH) terminující výjimkou i přes `-ErrorAction SilentlyContinue`
  (`Start-Process` tohle ignoruje u file-not-found) - opraveno na plnou cestu
  `$env:ProgramFiles\meetily\meetily.exe` obalenou v try/catch.

Celý flow je napsaný feature-parity s Mac verzí: `install.ps1` (admin práva,
místo na disku, zámek proti souběžnému běhu), `winget` instalace Python +
ffmpeg, jeden venv s `whisperx`/`pyannote-audio`/`faster-whisper`, HF
onboarding, automatická instalace appky Meetily (`.msi`, tichý `msiexec`),
port watcher skriptů (`meetily_watcher.py`, `meetily_autowatch.py`,
`export_transcript.py`, `apply_speaker_names.py`, `meetily_launch_prompt.py`),
registrace dvou úloh v Task Scheduleru (běh na pozadí).

Test doběhl až po instalaci appky Meetily a registraci obou Task Scheduler
úloh (po opravě elevace výše). `DB_PATH` je teď ověřený proti reálné databázi.
Zbývá neověřené:
- `src/payload/click_meetily_record.ps1` - klikání na tlačítko "Nahrávat" přes
  Windows UI Automation (heuristika podle velikosti tlačítka, převzatá z Mac
  AppleScriptu - Windows struktura appky není ověřená).
- Celý end-to-end běh watcher pipeline na skutečné nahrávce (přepis +
  diarizace + zápis zpět do Meetily databáze) - zatím otestováno jen to, že
  scheduled task dojede bez pádu na prázdné DB, ne na reálné nahrávce.

Landing page (`docs/index.html`) má tři cesty instalace: dvojklik na
`docs/Nainstalovat-Meetily.zip` (primární, doporučená pro netechnické
uživatele - `.bat` uvnitř se sám povýší na správce přes UAC a spustí
bootstrap), Path A přes `CLAUDE.md` (poslat odkaz Claude Code), nebo ruční
PowerShell příkaz (`irm ... | iex`). Distribuce jako `.zip` místo holého
`.bat` obchází Chrome/Edge varování "tento typ souboru může poškodit
počítač" (to je čistě podle přípony souboru) - zůstává jen mírnější Windows
dialog "Neznámý vydavatel" při spuštění, který se objevuje u každého
staženého skriptu bez placeného code-signing certifikátu.

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
| System Events UI-scripting (klik na "Nahrávat") | Windows UI Automation (`System.Windows.Automation`) |
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
src/payload/meetily_launch_prompt.py      # dialog "Chcete začít nahrávat?" při startu appky
src/payload/export_transcript.py          # export do sdílené složky + mapování jmen mluvčích
src/payload/apply_speaker_names.py        # aplikuje ručně vyplněná jména mluvčích
src/payload/click_meetily_record.ps1      # klik na tlačítko nahrávání (UI Automation)
src/payload/transcribe_meeting.ps1        # diarizace + přepis jednoho audio souboru
```

## Poznámka k diakritice

Skripty vypisují texty do konzole/dialogů bez diakritiky (`Vitej!` místo
`Vítej!`). Windows PowerShell 5.1 bez BOM v `.ps1` souboru občas špatně
interpretuje UTF-8 řetězcové literály (rozbitá diakritika v konzoli i v
dialogových oknech) - vynechání diakritiky je jednodušší a spolehlivější než
řešit BOM/kódování konzole na neznámé cílové mašině. Ověří se na reálném
Windows stroji a případně se to doladí.
