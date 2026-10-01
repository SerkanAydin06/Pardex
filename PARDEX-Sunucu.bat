@echo off
chcp 65001 >nul
title PARDEX Sunucusu
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js bulunamadi. Kuruluyor...
  winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
  echo.
  echo Kurulum bitti. Bu pencereyi kapatip PARDEX-Sunucu.bat dosyasini tekrar ac.
  pause
  exit /b
)
node host\pardex_host.js %*
pause
