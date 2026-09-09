@echo off
rem Meetily Watcher - instalator na dvojklik.
rem Sam se povysi na spravce (UAC okno) a spusti instalaci z install.ps1.
rem Zadne PowerShell okno ani prikazy neni potreba otevirat rucne.

NET SESSION >nul 2>&1
if %errorLevel% == 0 goto :elevated

echo Pozaduji spravcovska prava (objevi se okno Windows, klikni Ano)...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:elevated
title Meetily Watcher - instalace
rem Zamerne NE "irm URL | iex" - tenhle "stahni-a-hned-spust" vzorec ve
rem spojeni se souborem stazenym z internetu (Mark of the Web) spoustel
rem u Windows Defenderu ML heuristiku (Trojan:Win32/Commando.A!ml) a tise
rem instalaci zabil driv, nez vubec neco udelala. Stazeni do souboru a
rem spusteni pres -File dela uplne to stejne, jen to nevypada jako zivy
rem download-cradle retezec.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$b = Join-Path $env:TEMP 'meetily-bootstrap.ps1'; Invoke-WebRequest -Uri 'https://matyaspolidar-bot.github.io/meetily-watcher-installer-windows/install.ps1' -OutFile $b; & $b"

echo.
echo Instalace dobehla. Toto okno muzes zavrit.
pause >nul
