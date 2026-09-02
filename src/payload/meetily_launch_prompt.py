#!/usr/bin/env python3
"""Běží pořád na pozadí. Jakmile detekuje, že se Meetily právě spustilo
(přechod ze 'neběží' na 'běží'), zeptá se uživatele dialogem, jestli chce
začít nahrávat, a pokud ano, klikne na tlačítko nahrávání za něj.

Analogie meetily_launch_prompt.py z Mac verze - tam pgrep/osascript/System
Events, tady tasklist/PowerShell MessageBox/UI Automation.
"""
import subprocess
import time
from datetime import datetime
from pathlib import Path

POLL_INTERVAL_SECONDS = 2
WINDOW_READY_DELAY_SECONDS = 2
RECOVER_DIALOG_MAX_WAIT_SECONDS = 300
CLICK_SCRIPT = Path(__file__).parent / "click_meetily_record.ps1"

# Meetily po startu obcas nejdriv samo ukaze "Recover Interrupted Meetings"
# (kdyz se minula nahravka poradne nezastavila) - dokud tohle okno visi pres
# appku, hledani tlacitka nahravani selze. Musime pockat, az ho uzivatel zavre.
# POZOR: presna struktura Windows UI stromu NENI overena, viz click_meetily_record.ps1.
RECOVER_DIALOG_CHECK_SCRIPT = """
Add-Type -AssemblyName UIAutomationClient
$proc = Get-Process -Name "meetily" -ErrorAction SilentlyContinue
if (-not $proc) { Write-Output "no"; exit }
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)
$window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
if (-not $window) { Write-Output "no"; exit }
$nameCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Recover Interrupted Meetings")
$found = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $nameCond)
if ($found) { Write-Output "yes" } else { Write-Output "no" }
"""

ASK_DIALOG_SCRIPT = """
Add-Type -AssemblyName System.Windows.Forms
$result = [System.Windows.Forms.MessageBox]::Show(
    "Chcete zacit nahravat schuzku?", "Meetily",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question)
Write-Output $result
"""


def log(message: str) -> None:
    print(f"[{datetime.now().isoformat(timespec='seconds')}] {message}", flush=True)


def run_powershell(script: str) -> str:
    result = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
        capture_output=True, text=True,
    )
    return result.stdout.strip()


def is_meetily_running() -> bool:
    result = subprocess.run(
        ["tasklist", "/FI", "IMAGENAME eq meetily.exe"],
        capture_output=True, text=True,
    )
    return "meetily.exe" in result.stdout.lower()


def is_recover_dialog_showing() -> bool:
    return run_powershell(RECOVER_DIALOG_CHECK_SCRIPT) == "yes"


def wait_for_recover_dialog_to_close() -> None:
    waited = 0
    announced = False
    while is_recover_dialog_showing():
        if not announced:
            log("Appka ukazuje 'Recover Interrupted Meetings' - čekám, až to uživatel zavře.")
            announced = True
        if waited >= RECOVER_DIALOG_MAX_WAIT_SECONDS:
            log("Okno 'Recover Interrupted Meetings' visí moc dlouho, vzdávám to pro tentokrát.")
            return
        time.sleep(POLL_INTERVAL_SECONDS)
        waited += POLL_INTERVAL_SECONDS


def ask_and_maybe_record() -> None:
    log("Meetily se spustilo, zobrazuji dialog...")
    answer = run_powershell(ASK_DIALOG_SCRIPT)
    log(f"Odpověď dialogu: {answer!r}")
    if answer == "Yes":
        log("Uživatel klikl Ano, spouštím click_meetily_record.ps1...")
        click_result = subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(CLICK_SCRIPT)],
            capture_output=True, text=True,
        )
        log(
            f"Výsledek kliknutí: returncode={click_result.returncode} "
            f"stdout={click_result.stdout.strip()!r} stderr={click_result.stderr.strip()!r}"
        )
    else:
        log("Uživatel klikl Ne (nebo dialog selhal), nic neklikám.")


def main() -> None:
    log("Hlídač spuštěn, čekám na start Meetily...")
    was_running = is_meetily_running()
    while True:
        time.sleep(POLL_INTERVAL_SECONDS)
        now_running = is_meetily_running()
        if now_running and not was_running:
            log("Zaznamenán start Meetily.")
            time.sleep(WINDOW_READY_DELAY_SECONDS)
            wait_for_recover_dialog_to_close()
            ask_and_maybe_record()
        was_running = now_running


if __name__ == "__main__":
    main()
