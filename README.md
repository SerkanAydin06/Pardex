# PARDEX

PARDEX, VEX, Korsanların Hazinesi ve Fırtına Vadisi gibi oyunları tek uygulamada toplayacak Godot 4.7 tabanlı game hub / launcher projesidir.

## Mevcut durum

- 1440×900 taban çözünürlüklü, yeniden boyutlandırılabilir ana uygulama
- Kütüphane ekranı
- VEX, Korsanların Hazinesi ve Fırtına Vadisi kartları
- Ayrı Arkadaşlar / Odalar / Ayarlar ekranları
- Yerel profil adı kaydı
- Uygulama içinden güvenli çıkış
- Godot tarafında `PardexOnline` WebSocket istemcisi
- Otomatik reconnect, heartbeat ve kısa kopmalarda session recovery
- Cihazda kalıcı anonim PARDEX kimliği ve `px_...` hesap ID'si
- Bozuk/uygunsuz yerel kimlik dosyasını otomatik doğrulama ve güvenli yeniden üretme
- Tek kullanımlık kurtarma koduyla hesabı başka bilgisayara taşıma
- Kurtarma sonrası önceki cihaz kimliği ve açık eski oturumların iptal edilmesi
- Kullanıcı arama ve gerçek arkadaşlık sistemi
- Arkadaşlık isteği gönderme / kabul / ret / iptal
- Arkadaş kaldırma
- `Çevrimiçi / Uzakta / Meşgul / Oyunda` presence durumu
- Arkadaşın oyun/oda aktivitesini görme ve uygunsa doğrudan odasına katılma
- Arkadaşlara güvenli, süreli oda daveti gönderme / kabul / reddetme
- Arkadaş isteği ve oda daveti rozetleriyle uygulama içi bildirim merkezi
- Arkadaşlık ve hesap eşleme verilerinin sunucuda kalıcı dosyaya yazılması
- Node.js tabanlı PARDEX Online oda ve sosyal sunucusu
- Oda oluşturma ve 5 karakterlik oda kodu
- Oda koduyla katılma
- Oyuncu listesi, host bilgisi ve hazır durumu senkronizasyonu
- Odadan çıkma ve host devri
- Ayarlardan geliştirme sunucusu adresi değiştirme
- Sunucuda mesaj boyutu, hız sınırı, hello zaman aşımı ve açık oturumda hesap değiştirme koruması
- İstemci ses özelliği hazır olana kadar sunucu voice relay'inin varsayılan kapalı tutulması
- Graceful shutdown desteği
- Docker ile deploy edilebilir sunucu paketi
- Railway üzerinde çalışan production PARDEX Online servisi
- Railway Volume üzerinde kalıcı sosyal/hesap verisi
- GitHub Actions üzerinde oda, sosyal, davet, presence, hardening ve account-recovery WebSocket smoke testleri
- GitHub Actions üzerinde Docker build ve gerçek container `/health` kontrolü
- GitHub Actions üzerinde Godot 4.7.2 kaynak doğrulaması, asset import ve headless uygulama açılış testi
- Canlı `wss://` endpoint'e karşı production smoke testi; sunucu değişikliklerinde ve periyodik olarak çalışacak kontrol akışı

## Canlı PARDEX Online

Production WebSocket adresi:

```text
wss://pardex-online-production.up.railway.app
```

Railway production servisi `/health` health check ile izlenir. PARDEX istemcisi eski yerel varsayılan `ws://127.0.0.1:8765` ayarını görürse otomatik olarak resmi production servisine yönelir.

Arkadaşlık ve hesap kurtarma verilerinin deploy/restart sonrasında korunması için production sunucusunda `PARDEX_SOCIAL_DATA_PATH` kalıcı Railway Volume üzerindeki bir dosyaya yönlendirilmelidir. Mevcut production kurulumu `/data/social.json` kullanır. Ayrıntılar `server/DEPLOYMENT.md` dosyasındadır.

## PARDEX kimliği ve hesap kurtarma

PARDEX ilk çalıştırmada cihazda 256-bit rastgele bir kimlik anahtarı oluşturur ve bunu `user://pardex_identity.cfg` içinde saklar. Sunucu bu anahtardan anonim bir `px_...` hesap kimliği üretir; ham cihaz anahtarı sosyal veri dosyasına yazılmaz.

Ayarlar → **Hesap Kurtarma** bölümünden tek kullanımlık bir kurtarma kodu üretilebilir. Kod istemcide oluşturulur; sunucuda yalnız domain-separated SHA-256 özeti saklanır. Kodun düz metni sunucu sosyal veri dosyasına kaydedilmez.

Yeni bilgisayarda kurtarma kodu girildiğinde:

1. Aynı `px_...` hesap kimliği geri alınır.
2. Profil adı ve arkadaş ilişkileri korunur.
3. Kurtarma kodu anında tek kullanımlık olarak geçersiz olur.
4. Eski cihazın kayıtlı kimlik eşlemesi kaldırılır ve açık eski oturumları kapatılır.
5. Launcher güvenlik için otomatik olarak yeni bir kurtarma kodu üretir.

Kurtarma kodu parola gibi saklanmalıdır. PARDEX şu aşamada e-posta/parola hesabı kullanmaz; kurtarma kodunu da kaybeden ve eski cihazına erişemeyen kullanıcı için sunucu tarafında manuel hesap kurtarma akışı yoktur.

## Oyunların durumu

Oyunlar hâlâ geliştirme aşamasında olduğu için şu anda Windows `.exe` exportları PARDEX'e bağlanmıyor. Geliştirme ortamında Korsanların Hazinesi PARDEX oda/session argümanlarıyla açılabiliyor; paketlenmiş launcher için kurulum, sürüm manifesti, güncelleme ve gerçek `OYNA` akışı oyun yeterince hazır olduğunda eklenecek.

İlk gerçek oyun entegrasyonu Korsanların Hazinesi ile yapılacak.

## Yerel geliştirme testi

Yerel sunucuyu çalıştırmak için:

```bash
cd server
npm install
npm start
```

Yerel geliştirme adresi:

```text
ws://127.0.0.1:8765
```

Tüm oda, sosyal ve hesap kurtarma entegrasyon testlerini çalıştırmak için:

```bash
npm test
```

Godot kaynak ve gerçek açılış kontrolleri GitHub Actions'taki `PARDEX Godot CI` akışında çalışır. Production WebSocket akışı ayrıca `PARDEX Online Production Smoke` tarafından kontrol edilir.

Aynı ağdaki başka bir bilgisayar sunucu bilgisayarının LAN IP adresini kullanabilir. Production kullanımında son kullanıcı sunucu adresi girmeyecek; PARDEX doğrudan resmi online servise bağlanır.

## İnternet dağıtımı

PARDEX Online sunucusu `server/` klasöründen Docker ile dağıtıma hazırdır. Railway için ayrıntılı kurulum ve kalıcı sosyal veri notları:

```text
server/DEPLOYMENT.md
```

## Sıradaki teknik aşama

Sosyal çekirdeğin ana parçaları tamamlandı: kalıcı cihaz kimliği, arkadaşlık, session recovery, oda daveti, bildirim merkezi, presence, arkadaş odasına doğrudan katılma ve güvenli hesap kurtarma/cihaz transferi çalışıyor.

Sıradaki öncelikler:

1. Oyun oturumunu `lobby → launching → in_game → ended` olarak izleyen gerçek game lifecycle.
2. Korsanların Hazinesi Windows exportu hazır olduğunda launcher manifesti, kurulum/güncelleme ve gerçek `OYNA` akışı.
3. Kullanıcı sayısı büyümeden önce dosya tabanlı sosyal depodan SQLite/PostgreSQL gibi daha ölçeklenebilir bir veri katmanına geçiş planı.
4. İleride istenirse e-posta/parola veya harici kimlik sağlayıcısıyla ikinci seviye hesap kurtarma katmanı.
