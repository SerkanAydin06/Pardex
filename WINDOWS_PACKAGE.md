# PARDEX Windows Paketi

PARDEX, paketlenmiş sürümde Korsanların Hazinesi'ni varsayılan olarak şu yoldan başlatır:

`games\korsanlar\KorsanlarinHazinesi.exe`

Repo içindeki `tools\package_windows.ps1` hem PARDEX'i hem de yan klasördeki `Korsanlarin-Hazinesi` projesini export eder ve bu klasör yapısını otomatik oluşturur.

## Gereksinimler

- Godot 4.7.2
- Godot 4.7.2 Windows export templates
- `Pardex` ve `Korsanlarin-Hazinesi` repolarının varsayılan olarak aynı üst klasörde bulunması

## Paket oluşturma

PARDEX repo kökünde PowerShell açıp:

```powershell
.\tools\package_windows.ps1 -DistributionUrl "https://ALAN-ADIN" -GodotExe "C:\Godot\Godot_v4.7.2-stable_win64.exe"
```

Korsan repo başka bir yerdeyse:

```powershell
.\tools\package_windows.ps1 `
  -DistributionUrl "https://ALAN-ADIN" -GodotExe "C:\Godot\Godot_v4.7.2-stable_win64.exe" `
  -KorsanProject "D:\Projeler\Korsanlarin-Hazinesi"
```

Başarılı olduğunda:

- `dist\PARDEX-Windows\PARDEX.exe`
- `dist\PARDEX-Windows\PARDEX.pck`
- `dist\PARDEX-Windows\games\korsanlar\KorsanlarinHazinesi.exe`
- `dist\PARDEX-Windows\games\korsanlar\KorsanlarinHazinesi.pck`
- `dist\PARDEX-Windows.zip`

oluşturulur.

Dağıtılacak paket `PARDEX-Windows.zip` dosyasıdır. Kullanıcı klasör yapısını değiştirmeden ZIP'i açıp `PARDEX.exe` çalıştırmalıdır.

İstenirse Korsan executable yolu `PARDEX_KORSAN_EXECUTABLE` ortam değişkeniyle override edilebilir.

## Kurulum dosyası ve otomatik güncelleme

Bilgisayarda [Inno Setup 6](https://jrsoftware.org/isdl.php) kuruluysa paket betiği ayrıca `dist\PARDEX-Setup.exe` üretir (`tools\pardex_installer.iss`). Kurulum yönetici izni istemez, PARDEX'i `%LOCALAPPDATA%\Programs\PARDEX` altına kurar ve kısayol oluşturur.

Yeni sürüm yayınlamak için `APP_VERSION` ve `project.godot` sürümünü artır, kalıcı `-DistributionUrl` ile paketi oluştur ve [bağımsız dağıtım yönergesindeki](distribution/README.md) yayınlama aracını çalıştır. Paketler kendi HTTPS hizmetinde barındırılır; GitHub Release kullanılmaz.

Pardex açılışta ve 15 dakikada bir `channel.json` dosyasını kontrol eder. Uygulama güncellemesi Windows export sürümünde çalışır; paket boyutu ve SHA-256 doğrulanır, kurulum mevcut dizine yapılır ve Pardex tekrar açılır. Kurulu oyunlar ayrı sürüm klasörlerinde tutulur; yeni katalog oyunları indirilebilir. Canlı dağıtım adresi ayarlanmadan kullanıcıya paket gönderilmemelidir.
