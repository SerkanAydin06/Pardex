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
  "$ProgressPreference='SilentlyContinue';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "$all=Invoke-RestMethod -UseBasicParsing 'https://nodejs.org/dist/index.json';" ^
  "$v=[string](@($all | Where-Object { $_.lts })[0].version);" ^
  "if (-not $v.StartsWith('v')) { throw 'Node.js surumu bulunamadi.' };" ^
  "Write-Host ('Node.js '+$v+' indiriliyor...');" ^
  "New-Item -ItemType Directory -Force 'host\bin' | Out-Null;" ^
  "$zip='host\bin\node-download.zip'; $tmp='host\bin\node-download';" ^
  "Invoke-WebRequest -UseBasicParsing ('https://nodejs.org/dist/'+$v+'/node-'+$v+'-win-x64.zip') -OutFile $zip;" ^
  "if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force };" ^
  "Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force;" ^
  "if (Test-Path -LiteralPath 'host\bin\node') { Remove-Item -LiteralPath 'host\bin\node' -Recurse -Force };" ^
  "Move-Item -LiteralPath ($tmp+'\node-'+$v+'-win-x64') -Destination 'host\bin\node';" ^
  "Remove-Item -LiteralPath $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue"
if not exist "%PARDEX_NODE_DIR%\node.exe" (
  echo.
  echo Node.js indirilemedi. Internet baglantisini kontrol edip tekrar dene.
  pause
  exit /b 1
)

:run
if defined PARDEX_NODE_DIR set "PATH=%PARDEX_NODE_DIR%;%PATH%"
node host\pardex_host.js %*
if /i not "%~1"=="--gizli" pause
