param(
    [string]$GodotExe = "godot",
    [string]$KorsanProject = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

function Invoke-GodotExport {
    param(
        [string]$ProjectDir,
        [string]$Preset,
        [string]$OutputPath
    )

    $parent = Split-Path -Parent $OutputPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    Write-Host "Exporting $ProjectDir -> $OutputPath"
    & $GodotExe --headless --path $ProjectDir --export-release $Preset $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Godot export failed for '$ProjectDir' with exit code $LASTEXITCODE. Make sure Godot 4.7.2 export templates are installed."
    }
    if (-not (Test-Path $OutputPath)) {
        throw "Expected export was not created: $OutputPath"
    }
}

$PardexProject = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if ([string]::IsNullOrWhiteSpace($KorsanProject)) {
    $KorsanProject = Join-Path (Split-Path -Parent $PardexProject) "Korsanlarin-Hazinesi"
}
if (-not (Test-Path (Join-Path $KorsanProject "project.godot"))) {
    throw "Korsan project was not found at '$KorsanProject'. Pass -KorsanProject with the repository path."
}
$KorsanProject = (Resolve-Path $KorsanProject).Path

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $PardexProject "dist\PARDEX-Windows"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

if (Test-Path $OutputDir) {
    Remove-Item -Recurse -Force $OutputDir
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$PardexExe = Join-Path $OutputDir "PARDEX.exe"
$KorsanDir = Join-Path $OutputDir "games\korsanlar"
$KorsanExe = Join-Path $KorsanDir "KorsanlarinHazinesi.exe"

Invoke-GodotExport -ProjectDir $PardexProject -Preset "Windows Desktop" -OutputPath $PardexExe
Invoke-GodotExport -ProjectDir $KorsanProject -Preset "Windows Desktop" -OutputPath $KorsanExe

$requiredFiles = @(
    $PardexExe,
    (Join-Path $OutputDir "PARDEX.pck"),
    $KorsanExe,
    (Join-Path $KorsanDir "KorsanlarinHazinesi.pck")
)
foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        throw "Bundle is incomplete. Missing file: $file"
    }
}

$zipPath = "$OutputDir.zip"
if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}
Compress-Archive -Path (Join-Path $OutputDir "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host ""
Write-Host "PARDEX Windows bundle created successfully:"
Write-Host "  Folder: $OutputDir"
Write-Host "  ZIP:    $zipPath"
Write-Host ""
Write-Host "Expected runtime game path: games\korsanlar\KorsanlarinHazinesi.exe"
