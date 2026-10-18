# PARDEX Windows paketi

`tools/package_windows.ps1` yalnız Pardex'i dışa aktarır. Kurulum ve ZIP hiçbir oyun içermez; Korsan projesi paketleme sırasında gerekli değildir.

## Gereksinimler

- Godot 4.7.x ve kullandığınız sürümle aynı Windows export templates.
- Otomatik güncelleme için gereken `PARDEX-Setup.exe` çıktısını oluşturmak üzere Inno Setup 6.

## Paket oluşturma

PowerShell'de (Godot yolunu bilgisayarınıza göre değiştirin):

```powershell
.\tools\package_windows.ps1 -GodotExe "C:\Godot\Godot.exe" -DistributionUrl "https://pardex-distribution.srknydn88.workers.dev"
```

Betik GUI veya konsol Godot işleminin bitmesini bekler. `dist/PARDEX-Windows` çıktı klasörü yeniden oluşturulur. Çıktılar:

- `dist/PARDEX-Windows/PARDEX.exe` ve `PARDEX.pck`
- Aynı klasörde `pardex-distribution.json`
- `dist/PARDEX-Windows.zip`
- Inno Setup kuruluysa `dist/PARDEX-Setup.exe`

EXE ve PCK birlikte kalmalıdır. Kullanıcılara Setup dağıtılır; kurulum kullanıcı başına `%LOCALAPPDATA%/Programs/PARDEX` altına yapılır.

## Oyunları ayrı yayınlama

Korsan'ı kendi Godot projesinden Windows Desktop preset'iyle Pardex projesinin `dist/games/korsanlar/KorsanlarinHazinesi.exe` yoluna dışa aktarın. EXE, PCK ve gerekli diğer oyun dosyaları bu ayrı klasörde olmalıdır. Bu klasör Pardex kurulumuna eklenmez.

`distribution/README.md` içindeki yayın tanımıyla oyunları ve uygulama kurulumunu ayrı paketler olarak hazırlayın. Paketleri önce, `channel.json` dosyasını en son R2'ye yükleyin. Katalog yayınlanınca kullanıcı Pardex içinden oyunları indirir; indirilen oyunlar uygulama kurulumundan ayrı `user://games` altında tutulur.

## Uygulama güncellemeleri

Pardex açılışta ve 15 dakikada bir kataloğu kontrol eder. Yeni sürüm bulunduğunda kullanıcıya onay penceresi gösterir; onaydan sonra paket boyutu ve SHA-256 doğrulanır, Setup çalıştırılır ve Pardex yeniden açılır. Açık oyunlar önce kapatılmalıdır. GitHub'a kod göndermek tek başına güncelleme yayınlamaz: APP_VERSION ve project.godot sürümünü artırıp yeni Setup ve kataloğu R2'ye yükleyin.

Eski oyun içeren kurulumun üzerine kurmak eski oyun dosyalarını silmez. Temiz kurulumu sınamak için ayrı bir kurulum klasörü seçin. Kullanıcının oyunları ve kayıtları otomatik silinmez.
