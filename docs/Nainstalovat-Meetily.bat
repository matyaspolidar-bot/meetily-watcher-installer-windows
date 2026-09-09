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
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://matyaspolidar-bot.github.io/meetily-watcher-installer-windows/install.ps1 | iex"

echo.
echo Instalace dobehla. Toto okno muzes zavrit.
pause >nul
