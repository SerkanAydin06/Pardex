# PARDEX yayınlama: sürümü artırır, kurulum dosyasını üretir ve arkadaşların
# PARDEX'i açınca güncellenecek şekilde Cloudflare R2'ye yükler.
# Kişisel ayarlar (Godot yolu, hesap kimliği) tools\yayinla.local.json'da
# saklanır ve Git'e eklenmez. Gizli anahtar istemez: R2 yüklemesi AWS CLI'nin
# kayıtlı "pardex-r2" profilini kullanır.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Url = "https://pardex-distribution.srknydn88.workers.dev"
$SettingsPath = Join-Path $PSScriptRoot "yayinla.local.json"
$SpecPath = Join-Path $Root "release.local.json"
$MainPath = Join-Path $Root "scripts\main.gd"

function Fail($message) {
    Write-Host ""
    Write-Host "HATA: $message" -ForegroundColor Red
    Read-Host "Kapatmak icin Enter'a bas"
    exit 1
}

function Ask($question, $default) {
    $suffix = if ($default) { " [$default]" } else { "" }
    $answer = Read-Host "$question$suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $default }
    return $answer.Trim()
}

function Newer($candidate, $current) {
    $a = $candidate.Split("."); $b = $current.Split(".")
    for ($i = 0; $i -lt [Math]::Max($a.Count, $b.Count); $i++) {
        $x = if ($i -lt $a.Count) { [int]$a[$i] } else { 0 }
        $y = if ($i -lt $b.Count) { [int]$b[$i] } else { 0 }
        if ($x -ne $y) { return $x -gt $y }
    }
    return $false
}

Write-Host ""
Write-Host "PARDEX yayinla" -ForegroundColor Cyan
Write-Host "--------------"

# 1. Kisisel ayarlar (ilk calistirmada sorulur, sonra hatirlanir)
$settings = @{}
if (Test-Path $SettingsPath) {
    (Get-Content $SettingsPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
}
$settings.godot = Ask "Godot programinin yolu" $settings.godot
if (-not $settings.godot -or -not (Test-Path $settings.godot)) { Fail "Godot programi bulunamadi: $($settings.godot)" }
$settings.account = Ask "Cloudflare hesap kimligi (32 karakter, gizli degil)" $settings.account
if ($settings.account -notmatch '^[a-f0-9]{32}$') { Fail "Hesap kimligi 32 karakterlik kucuk harf/rakam olmali." }
$settings | ConvertTo-Json | Set-Content -Path $SettingsPath -Encoding UTF8

foreach ($tool in @("python", "aws")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Fail "$tool bulunamadi. Kurulu oldugundan ve PATH'te oldugundan emin ol." }
}
$env:AWS_PROFILE = "pardex-r2"

# 2. Surum numarasi
$main = Get-Content $MainPath -Raw -Encoding UTF8
$match = [regex]::Match($main, 'const APP_VERSION := "([0-9.]+)"')
if (-not $match.Success) { Fail "scripts\main.gd icinde APP_VERSION bulunamadi." }
$current = $match.Groups[1].Value
$parts = $current.Split(".")
$parts[$parts.Count - 1] = [string]([int]$parts[$parts.Count - 1] + 1)
$version = Ask "Yeni surum (su an $current)" ($parts -join ".")
if ($version -notmatch '^[0-9]{1,6}(\.[0-9]{1,6}){0,3}$') { Fail "Surum 1.2.3 biciminde olmali." }
if (-not (Newer $version $current)) { Fail "Yeni surum $current'dan buyuk olmali; yoksa arkadaslarin guncellemeyi gormez." }

# 3. Surumu yaz ve kurulum dosyasini uret. Hata olursa eski surum geri yazilir.
$utf8 = New-Object System.Text.UTF8Encoding($false)
$setup = Join-Path $Root "dist\PARDEX-Setup.exe"
# Eski bir kurulum dosyasi yeni sanilmasin.
if (Test-Path $setup) { Remove-Item -Force $setup }
[IO.File]::WriteAllText($MainPath, $main.Replace($match.Value, "const APP_VERSION := `"$version`""), $utf8)
try {
    & (Join-Path $PSScriptRoot "package_windows.ps1") -GodotExe $settings.godot -DistributionUrl $Url
} catch {
    [IO.File]::WriteAllText($MainPath, $main, $utf8)
    Fail "Kurulum dosyasi uretilemedi: $($_.Exception.Message)"
}
if (-not (Test-Path $setup)) {
    [IO.File]::WriteAllText($MainPath, $main, $utf8)
    Fail "dist\PARDEX-Setup.exe olusmadi. Inno Setup 6 kurulu mu?"
}

# 4. Katalog: oyunlar korunur, yalniz PARDEX surumu degisir.
$spec = if (Test-Path $SpecPath) { Get-Content $SpecPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{ games = @() } }
if (-not $spec.PSObject.Properties["games"]) { $spec | Add-Member games @() }
$launcher = [pscustomobject]@{ version = $version; setup = $setup }
if ($spec.PSObject.Properties["launcher"]) { $spec.launcher = $launcher } else { $spec | Add-Member launcher $launcher }
[IO.File]::WriteAllText($SpecPath, ($spec | ConvertTo-Json -Depth 8), $utf8)

# 5. Hazirla ve yukle: once paketler, en son katalog (yarim yayin olmaz).
Push-Location $Root
try {
    python tools/publish_release.py --spec release.local.json --url $Url --output distribution/public
    if ($LASTEXITCODE -ne 0) { throw "Yayin hazirlanamadi." }
    python tools/upload_r2.py --account-id $settings.account --url $Url
    if ($LASTEXITCODE -ne 0) { throw "Cloudflare'a yuklenemedi. AWS 'pardex-r2' profilini ve internet baglantisini (WARP) kontrol et." }
} catch {
    Pop-Location
    # Yayin olmadi: surum numarasi da eski haline doner, tekrar denenebilir.
    [IO.File]::WriteAllText($MainPath, $main, $utf8)
    Fail $_.Exception.Message
}
Pop-Location

Write-Host ""
Write-Host "Yayinlandi: PARDEX $version" -ForegroundColor Green
Write-Host "Arkadaslarin PARDEX'i acinca (ya da 15 dakika icinde) kendiliginden guncellenecek."
Write-Host "Surum degisikligini (scripts\main.gd) GitHub Desktop'ta commit edip gonder."
Read-Host "Kapatmak icin Enter'a bas"
