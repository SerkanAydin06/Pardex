# PARDEX ağ testi: sunucu panelinin adres yayınladığı dağıtım sunucusuna
# (workers.dev) bu bilgisayardan ulaşılabiliyor mu? Yalnız okuma yapar;
# anahtar kullanmaz, ayar değiştirmez. Sunucu Paneli › Ağ testi bunu -Panel ile
# çalıştırır.

param([switch]$Panel)

$ErrorActionPreference = "Continue"
if ($Panel) { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) }
$HostName = "pardex-distribution.srknydn88.workers.dev"
$Url = "https://$HostName/online.json"
$Root = Split-Path -Parent $PSScriptRoot
$Node = Join-Path $Root "host\bin\node\node.exe"

function Show($label, $ok, $detail) {
    $mark = if ($ok) { "[ OK  ]" } else { "[HATA ]" }
    $color = if ($ok) { "Green" } else { "Red" }
    Write-Host ("{0} {1}" -f $mark, $label) -ForegroundColor $color
    if ($detail) { Write-Host ("        " + $detail) }
}

function CurlTest($arguments) {
    # stderr satirlarini duz metne cevir; PowerShell 5 onlari kirmizi hata kaydi gibi basiyor.
    $output = & curl.exe @arguments 2>&1 | ForEach-Object { "$_" } | Out-String
    return $output.Trim()
}

Write-Host ""
Write-Host "PARDEX ag testi" -ForegroundColor Cyan
Write-Host "----------------"

# 1. Dağıtım sunucusu (curl, TCP)
$r1 = CurlTest @("-sS", "-o", "NUL", "-w", "%{http_code} %{remote_ip} HTTP/%{http_version}", "--max-time", "15", $Url)
$ok1 = $r1 -match "^(200|404) "
Show "Dagitim sunucusu (curl)" $ok1 $r1

# 2. Aynı Cloudflare IP'sine başka bir adla bağlantı: IP mi, ad mı engelleniyor?
$ip = (Resolve-DnsName $HostName -Type A -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress
if ($ip) {
    $r2 = CurlTest @("-sS", "-o", "NUL", "-w", "%{http_code} %{remote_ip}", "--max-time", "15", "--resolve", "www.cloudflare.com:443:$ip", "https://www.cloudflare.com/")
    $ok2 = $r2 -match "^[23]\d\d "
    Show "Ayni IP ($ip), farkli ad (www.cloudflare.com)" $ok2 $r2
} else {
    $ok2 = $false
    Show "DNS ($HostName)" $false "Adres cozulemedi."
}

# 3. Panelin kullandığı Node ile aynı istek
if (Test-Path $Node) {
    $r3 = & $Node -e "fetch('$Url').then(r=>console.log('HTTP '+r.status)).catch(e=>console.log((e.cause&&e.cause.code)||e.message))" 2>&1 | Out-String
    $r3 = $r3.Trim()
    $ok3 = $r3 -match "^HTTP (200|404)"
    Show "Sunucu paneli (Node)" $ok3 $r3
} else {
    $ok3 = $null
    Show "Sunucu paneli (Node)" $false "host\bin\node\node.exe bulunamadi; panel bir kez acilinca indirilir."
}

# 4. Ucretsiz Cloudflare adresleri: hangisine baglanti kesilmeden ulasiliyor?
# Herhangi bir HTTP yaniti (404 dahil) "ulasiliyor" demektir.
Write-Host ""
Write-Host "Ucretsiz Cloudflare adresleri:" -ForegroundColor Cyan
$free = [ordered]@{
    "pages.dev (Cloudflare Pages)" = "https://cloudflare-docs.pages.dev/"
    "r2.dev (R2 genel adres)" = "https://pub-00000000000000000000000000000000.r2.dev/"
    "r2.cloudflarestorage.com (R2 yukleme)" = "https://r2.cloudflarestorage.com/"
    "trycloudflare.com (oyuncu tuneli)" = "https://api.trycloudflare.com/"
}
foreach ($name in $free.Keys) {
    $r = CurlTest @("-sS", "-o", "NUL", "-w", "%{http_code}", "--max-time", "15", $free[$name])
    Show $name ($r -match "^[1-5]\d\d$") $r
}

Write-Host ""
Write-Host "Sonuc:" -ForegroundColor Cyan
if ($ok1 -and $ok3 -ne $false) {
    Write-Host "Dagitim sunucusuna ulasiliyor. Sunucu panelinde 'Baslat'a tekrar bas."
} elseif (-not $ok1 -and $ok2) {
    Write-Host "Cloudflare'a ulasiliyor ama 'workers.dev' adina giden baglanti kesiliyor."
    Write-Host "Bu ag (modem ya da internet saglayicisi) bu adi engelliyor olabilir."
} elseif (-not $ok1 -and -not $ok2) {
    Write-Host "Bu IP'deki Cloudflare'a hic ulasilamiyor; ag ya da guvenlik yazilimi baglantiyi kesiyor olabilir."
} else {
    Write-Host "Sonuclar karisik; bu sonuclarin ekran goruntusunu gonder."
}
if (-not $Panel) {
    Write-Host ""
    Write-Host "Bu pencerenin ekran goruntusunu Claude'a gonder."
    Read-Host "Kapatmak icin Enter'a bas"
}
