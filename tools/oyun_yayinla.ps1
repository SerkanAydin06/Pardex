# PARDEX oyun yayinlama: bir Godot oyununu Windows icin disa aktarir, PARDEX
# magazasina ekler (ya da yeni surumunu yayinlar) ve Cloudflare R2'ye yukler.
# Oyuncular oyunu PARDEX'ten indirir; yeni surumde "Guncelle" gorurler.
# Ayarlar: tools\yayinla.local.json (Godot yolu, hesap kimligi) ve
# release.local.json (yayinlanan oyunlar). Ikisi de Git'e eklenmez.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Url = "https://pardex-distribution.srknydn88.workers.dev"
$SettingsPath = Join-Path $PSScriptRoot "yayinla.local.json"
$SpecPath = Join-Path $Root "release.local.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)

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
    return $answer.Trim().Trim('"')
}

function NextVersion($current) {
    if (-not $current) { return "1.0.0" }
    $parts = $current.Split(".")
    $parts[$parts.Count - 1] = [string]([int]$parts[$parts.Count - 1] + 1)
    return $parts -join "."
}

Write-Host ""
Write-Host "PARDEX oyun yayinla" -ForegroundColor Cyan
Write-Host "-------------------"

# 1. Kisisel ayarlar (PARDEX-Yayinla.bat ile ayni dosya)
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
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Fail "$tool bulunamadi." }
}
$env:AWS_PROFILE = "pardex-r2"

# 2. Hangi oyun? Daha once yayinlananlar listelenir.
$spec = if (Test-Path $SpecPath) { Get-Content $SpecPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{} }
$games = @()
if ($spec.PSObject.Properties["games"]) { $games = @($spec.games) }
$old = $null
if ($games.Count -gt 0) {
    Write-Host ""
    Write-Host "Yayinlanan oyunlar:"
    for ($i = 0; $i -lt $games.Count; $i++) { Write-Host ("  {0}) {1}  (surum {2})" -f ($i + 1), $games[$i].title, $games[$i].version) }
    Write-Host "  0) Yeni oyun"
    $pick = Ask "Secim" "0"
    if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $games.Count) { $old = $games[[int]$pick - 1] }
}

$project = Ask "Oyunun Godot proje klasoru (icinde project.godot olan)" $(if ($old) { $old.project } else { "" })
if (-not $project -or -not (Test-Path (Join-Path $project "project.godot"))) { Fail "Bu klasorde project.godot yok: $project" }
$presets = Join-Path $project "export_presets.cfg"
if (-not (Test-Path $presets) -or -not (Select-String -Path $presets -Pattern 'name="Windows Desktop"' -Quiet)) {
    Fail "Oyun projesinde 'Windows Desktop' disa aktarma ayari yok. Godot'ta Proje > Disa Aktar > Ekle > Windows Desktop ile olustur."
}
$folderName = Split-Path $project -Leaf
$defaultId = ($folderName.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
if ($defaultId -notmatch '^[a-z]') { $defaultId = "oyun-" + $defaultId }
$id = Ask "Oyun kimligi (kucuk harf, bosluksuz; sonra degistirme)" $(if ($old) { $old.id } else { $defaultId })
if ($id -notmatch '^[a-z][a-z0-9_-]{0,47}$') { Fail "Kimlik kucuk harfle baslamali; yalniz a-z, 0-9, - ve _ olabilir." }
$title = Ask "Magazada gorunecek ad" $(if ($old) { $old.title } else { $folderName })
$version = Ask "Surum" $(NextVersion $(if ($old) { $old.version } else { "" }))
if ($version -notmatch '^[0-9]{1,6}(\.[0-9]{1,6}){0,3}$') { Fail "Surum 1.2.3 biciminde olmali." }
$description = Ask "Kisa tanitim cumlesi" $(if ($old) { $old.description } else { "" })
$players = Ask "Oyuncu sayisi (or. Tek oyunculu, 1-4 oyuncu)" $(if ($old) { $old.players } else { "Tek oyunculu" })
$genreText = Ask "Turler (virgulle, en cok 4)" $(if ($old -and $old.genres) { ($old.genres -join ", ") } else { "" })
$genres = @($genreText -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($genres.Count -gt 4) { Fail "En cok 4 tur yazilabilir." }
$cover = Ask "Kapak resmi (dikey, PNG/JPG; bos birakilabilir)" $(if ($old) { $old.cover } else { "" })
$banner = Ask "Afis resmi (genis, PNG/JPG; bos birakilabilir)" $(if ($old) { $old.banner } else { "" })
foreach ($image in @($cover, $banner)) {
    if ($image -and -not (Test-Path $image)) { Fail "Resim bulunamadi: $image" }
}

# Ayrintilar: uzun metinler UTF-8 .txt dosyalarindan okunabilir.
$details = @{}
foreach ($field in @("long_description", "requirements", "release_notes", "connection_modes")) {
    $labels = @{
        long_description = "Uzun aciklama"; requirements = "Sistem gereksinimleri"
        release_notes = "Guncelleme notlari"; connection_modes = "Oyun/baglanti turleri"
    }
    $details[$field] = if ($old -and $old.$field) { $old.$field } else { "" }
    $textPath = Ask "$($labels[$field]) icin UTF-8 .txt yolu (bos = mevcut bilgiyi koru)" ""
    if ($textPath) {
        if (-not (Test-Path $textPath -PathType Leaf)) { Fail "Metin dosyasi bulunamadi: $textPath" }
        $details[$field] = [IO.File]::ReadAllText($textPath, [Text.Encoding]::UTF8)
    }
}
$shotsDefault = if ($old -and $old.screenshots) { $old.screenshots -join ";" } else { "" }
$shotsText = Ask "Ekran goruntuleri (en cok 8 dosya yolu, ; ile ayir; silmek icin -)" $shotsDefault
$screenshots = @()
if ($shotsText -and $shotsText -ne "-") {
    $screenshots = @($shotsText -split ";" | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })
}
if ($screenshots.Count -gt 8) { Fail "En cok 8 ekran goruntusu eklenebilir." }
foreach ($shot in $screenshots) {
    if (-not (Test-Path $shot -PathType Leaf)) { Fail "Ekran goruntusu bulunamadi: $shot" }
}

# 3. Windows icin disa aktar (build\games\<kimlik>, her seferinde temiz)
$out = Join-Path $Root "build\games\$id"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force -Path $out | Out-Null
$exe = "$id.exe"
Write-Host ""
Write-Host "Oyun disa aktariliyor (biraz surebilir)..."
$arguments = '--headless --path "{0}" --export-release "Windows Desktop" "{1}"' -f $project, (Join-Path $out $exe)
$process = Start-Process -FilePath $settings.godot -ArgumentList $arguments -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0 -or -not (Test-Path (Join-Path $out $exe))) {
    Fail "Disa aktarma basarisiz (kod $($process.ExitCode)). Godot'ta bu surumun Windows export sablonlari kurulu mu?"
}

# 4. Katalogda bu oyunu ekle ya da yenile; diger oyunlar ve PARDEX surumu korunur.
$entry = [ordered]@{
    id = $id; title = $title; version = $version; directory = $out; executable = $exe
    description = $description; players = $players; genres = $genres
    cover = $cover; banner = $banner; project = $project
    screenshots = $screenshots
    long_description = $details.long_description; requirements = $details.requirements
    release_notes = $details.release_notes; connection_modes = $details.connection_modes
}
$games = @($games | Where-Object { $_.id -ne $id }) + @([pscustomobject]$entry)
$newSpec = [ordered]@{ games = $games }
if ($spec.PSObject.Properties["launcher"] -and $spec.launcher.setup) {
    if (Test-Path $spec.launcher.setup) {
        $newSpec.launcher = $spec.launcher
    } else {
        Fail "PARDEX kurulum dosyasi bulunamadi ($($spec.launcher.setup)). Once PARDEX-Yayinla.bat ile PARDEX'i bir kez yayinla."
    }
}
$previous = if (Test-Path $SpecPath) { [IO.File]::ReadAllText($SpecPath) } else { $null }
[IO.File]::WriteAllText($SpecPath, ($newSpec | ConvertTo-Json -Depth 8), $utf8)

# 5. Hazirla ve yukle: once paketler, en son katalog.
Push-Location $Root
try {
    python tools/publish_release.py --spec release.local.json --url $Url --output distribution/public
    if ($LASTEXITCODE -ne 0) { throw "Yayin hazirlanamadi (oyun klasoru, resimler ya da turleri kontrol et)." }
    python tools/upload_r2.py --account-id $settings.account --url $Url
    if ($LASTEXITCODE -ne 0) { throw "Cloudflare'a yuklenemedi. AWS 'pardex-r2' profilini ve WARP'i kontrol et." }
} catch {
    Pop-Location
    # Yayin olmadi: katalog dosyasi eski haline doner.
    if ($null -ne $previous) { [IO.File]::WriteAllText($SpecPath, $previous, $utf8) } else { Remove-Item -Force $SpecPath }
    Fail $_.Exception.Message
}
Pop-Location

Write-Host ""
Write-Host "Yayinlandi: $title $version" -ForegroundColor Green
Write-Host "Oyuncular PARDEX'i acinca (ya da 15 dakika icinde) magazada gorur; 'Indir' ya da 'Guncelle' ile kurar."
Read-Host "Kapatmak icin Enter'a bas"
