@echo off
chcp 65001 >nul
title PARDEX Sunucusu
cd /d "%~dp0"

rem Node.js: once PARDEX'in kendi kopyasi (host\bin\node), sonra kurulu surum.
set "PARDEX_NODE_DIR=%~dp0host\bin\node"
if exist "%PARDEX_NODE_DIR%\node.exe" goto run
for %%D in ("%ProgramFiles%\nodejs" "%LOCALAPPDATA%\Programs\nodejs") do (
  if exist "%%~D\node.exe" (
    set "PARDEX_NODE_DIR=%%~D"
    goto run
  )
)
where node >nul 2>nul
if not errorlevel 1 (
  set "PARDEX_NODE_DIR="
  goto run
)

echo Node.js indiriliyor (yalnizca ilk sefer, kurulum gerekmez)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "$v=(Invoke-RestMethod 'https://nodejs.org/dist/index.json' | Where-Object { $_.lts } | Select-Object -First 1).version;" ^
  "$zip=Join-Path $env:TEMP ('node-'+$v+'.zip');" ^
  "Invoke-WebRequest ('https://nodejs.org/dist/'+$v+'/node-'+$v+'-win-x64.zip') -OutFile $zip;" ^
  "$tmp=Join-Path $env:TEMP 'pardex-node';" ^
  "if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force };" ^
  "Expand-Archive $zip $tmp -Force;" ^
  "New-Item -ItemType Directory -Force 'host\bin' | Out-Null;" ^
  "if (Test-Path 'host\bin\node') { Remove-Item 'host\bin\node' -Recurse -Force };" ^
  "Move-Item (Join-Path $tmp ('node-'+$v+'-win-x64')) 'host\bin\node';" ^
  "Remove-Item $zip -Force"
if not exist "%PARDEX_NODE_DIR%\node.exe" (
  echo.
  echo Node.js indirilemedi. Internet baglantisini kontrol edip tekrar dene.
  pause
  exit /b 1
)

:run
if defined PARDEX_NODE_DIR set "PATH=%PARDEX_NODE_DIR%;%PATH%"
node host\pardex_host.js %*
pause
