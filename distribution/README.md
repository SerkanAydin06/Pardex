# GitHub'dan bağımsız PARDEX dağıtımı

Çalışma zamanı kendi kalıcı HTTPS adresini kullanır. Kaynak depo silinse bile dağıtım sunucusu, alan adı ve paketler kaldığı sürece güncellemeler çalışır. Kaynak kodu ve yayın dosyalarını ayrıca yedekleyin; bu işlem depoyu silmez.

## İlk dağıtım

1. Kalıcı alan adı/HTTPS adresini belirleyin. Oyuncuya dağıtılan `pardex-distribution.json` yalnız `{"url":"https://SENIN-ALAN-ADIN"}` içerir; yönetici anahtarı içermez. Adresi mümkünse değiştirmeyin; sağlayıcı taşınırken aynı alan adını koruyun.
2. Windows'ta `tools/package_windows.ps1 -DistributionUrl https://SENIN-ALAN-ADIN` ile paket oluşturun. Godot export şablonları ve Inno Setup gerekir. Setup kullanıcı başına kurulur. Güncelleme mevcut kurulum dizinini kullanır ve dağıtım ayarını korur.
3. `tools/publish_release.py` ile aşağıdaki yayın tanımından `channel.json` ve değişmez `packages/` dosyalarını üretin. Python 3.11+ gerekir. Dosya yolları komutun çalıştığı dizine göredir.
4. Bu dizini kendi HTTPS sunucunuza yükleyin: önce paketler, en son `channel.json`. Paket URL'leri doğrudan dosya döndürmeli; yönlendirme desteklenmez. Eski paketleri anında silmeyin: eski katalogla indiren kullanıcılar olabilir.

Örnek yerel yayın tanımı (özel yolları kendi bilgisayarınıza göre belirleyin):

```json
{
  "launcher": {"version":"0.2.0", "setup":"dist/PARDEX-Setup.exe"},
  "games":[
    {"id":"korsanlar", "title":"Korsanların Hazinesi", "version":"1.0.0",
     "directory":"dist/PARDEX-Windows/games/korsanlar", "executable":"KorsanlarinHazinesi.exe",
     "description":"Korsan macerası", "players":"1–4 oyuncu"}
  ]
}
```

```sh
python tools/publish_release.py --spec release.local.json --url https://SENIN-ALAN-ADIN --output distribution/public
```

Yeni oyun için listeye yeni, sabit bir `id` ekleyin. Yayın tanımı o anda sunulacak bütün oyunları içermelidir. Her oyun bağımsız Windows export dizini olmalı; EXE, PCK ve ihtiyaç duyduğu dosyalar birlikte paketlenir. Kayıtlar Godot `user://` içinde tutulmalı; uygulama kurulum dizinine kayıt yazan oyunların kayıt yönetimi önce düzeltilmelidir. Korsan dışındaki yeni oyunlar bağımsız EXE olarak açılır; Pardex resmî sunucu entegrasyonu oyun tarafında ayrıca uygulanmalıdır.

## Dağıtım ve adres servisi

Statik HTTPS barındırma güncellemeler için yeterlidir. Geçici resmî sunucu adresini panelden otomatik yayımlamak için bağımlılıksız Node 22+ servisi de sağlanır:

```sh
# PARDEX_PUBLISH_TOKEN: en az 32 karakterlik rastgele sır, yalnız yönetici/sunucu ortamında.
# PARDEX_RELEASE_DIR: public dizininin mutlak yolu.
node distribution/server.js
```

Servis varsayılan olarak `127.0.0.1:8780` üzerinde dinler; önüne HTTPS reverse proxy koyun. `GET /channel.json`, `GET /packages/<hash>.zip|exe` ve `GET /online.json` herkese açıktır. Yalnız `PUT /online.json` Bearer yayın anahtarıyla çalışır. Panelde **Dağıtım sunucusu yayın adresi** = `https://SENIN-ALAN-ADIN/online.json`, **Yayın anahtarı** = sunucudaki sır. Anahtarı kaynak depoya veya istemci paketine koymayın.

Başka bir hizmet kullanılıyorsa aynı PUT sözleşmesini karşılayabilir. Sabit resmî sunucu için `online.json` elle de yayımlanabilir: `{"online":"wss://OYUN-SUNUCUN"}`. Panel kapandığında adresi boşaltır.

## Güvenlik ve kurtarma

- HTTPS, paket boyutu ve SHA-256 kontrolü; yetkisiz yönlendirmeler reddedilir. Hash, HTTPS ile gelen kataloğa güvenmeye dayanır; bağımsız kod imzası değildir. Dağıtım sunucusunun yazma yetkisini koruyun.
- Hatalı katalogda mevcut katalog kullanılır. Ağ yoksa kurulu oyunlar korunur. Mevcut oyun sürümünü kullanma seçeneği vardır.
- Oyunlar `user://games/<id>/<version>-<hash>/` altına kurulur; kurulum başarılı olunca aktif sürüm kaydı değiştirilir. Eski sürüm klasörleri tutulur. Kayıtlar/kimlik dosyaları silinmez.
- İlk sürüm Windows x64 içindir; oyun ZIP'i en fazla 2 GiB, açılmış toplamı 8 GiB ve 4096 dosya olabilir. İndirme kesilirse tekrar denenir; kaldığı bayttan devam etme henüz yoktur.
- Windows EXE/Setup çalıştırılması ve kurulumun yeniden açılması ayrıca gerçek Windows makinede doğrulanmalıdır. İmzasız Setup için Windows uyarısı çıkabilir.
- Canlı adres yapılandırılmadan paket dağıtmayın. Eski GitHub güncelleyicili kullanıcılar bu sürümü bir kez elle kurmalıdır.
