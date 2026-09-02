# meetily-watcher-installer-windows

Windows instalátor Whisper/Meetily watcher pipeline pro Addvery konzultanty.
Sesterský repozitář k [`meetily-watcher-installer`](https://github.com/matyaspolidar-bot/meetily-watcher-installer)
(macOS verze) - stejný princip (Path A: pošli tenhle repo Claude Code zprávou,
nebo PowerShell příkaz z landing page jako záloha), ale Windows-nativní
mechanismy místo macOS.

## Stav: ve vývoji (kostra, v0.1.0)

Fáze 1-2 hotové: `install.ps1` + `stages.ps1` (admin práva, místo na disku,
zámek proti souběžnému běhu, `winget` instalace Python + ffmpeg, vytvoření
venv s `whisperx`/`pyannote-audio`/`faster-whisper`, HF onboarding). Zatím
chybí: automatická instalace appky Meetily (`.msi`/`.exe`), registrace úloh
v Task Scheduleru, port watcher skriptů a automatické klikání na "Nahrávat"
přes Windows UI Automation, landing page.

## Mapování mechanismů (Mac → Windows)

| Mac | Windows |
|---|---|
| bash | PowerShell |
| `curl \| bash` | `irm <url>/install.ps1 \| iex` |
| Homebrew | `winget install Python.Python.3.13`, `winget install Gyan.FFmpeg` |
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
docs/install.ps1            # bootstrap - stáhne + rozbalí + spustí install.ps1
src/install.ps1             # entrypoint
src/lib/gui.ps1              # dialogy (WinForms/VisualBasic)
src/lib/stages.ps1           # idempotentní instalační kroky
src/lib/hf_onboarding.ps1    # HuggingFace účet/licence/token flow
```

## Poznámka k diakritice

Skripty vypisují texty do konzole/dialogů bez diakritiky (`Vitej!` místo
`Vítej!`). Windows PowerShell 5.1 bez BOM v `.ps1` souboru občas špatně
interpretuje UTF-8 řetězcové literály (rozbitá diakritika v konzoli i v
dialogových oknech) - vynechání diakritiky je jednodušší a spolehlivější než
řešit BOM/kódování konzole na neznámé cílové mašině. Ověří se na reálném
Windows stroji a případně se to doladí.
