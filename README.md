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
- Kullanıcı arama ve gerçek arkadaşlık sistemi
- Arkadaşlık isteği gönderme / kabul / ret / iptal
- Arkadaş kaldırma
- `Çevrimiçi / Uzakta / Meşgul / Oyunda` presence durumu
- Arkadaşın oyun/oda aktivitesini görme ve uygunsa doğrudan odasına katılma
- Arkadaşlara güvenli, süreli oda daveti gönderme / kabul / reddetme
- Arkadaş isteği ve oda daveti rozetleriyle uygulama içi bildirim merkezi
- Arkadaşlık verilerinin sunucuda kalıcı dosyaya yazılması
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
- Railway Volume üzerinde kalıcı sosyal veri
- GitHub Actions üzerinde oda, sosyal, davet, presence ve hardening WebSocket smoke testleri
- GitHub Actions üzerinde Docker build ve gerçek container `/health` kontrolü
- GitHub Actions üzerinde Godot 4.7.2 kaynak doğrulaması, asset import ve headless uygulama açılış testi
- Canlı `wss://` endpoint'e karşı production smoke testi; sunucu değişikliklerinde ve periyodik olarak çalışacak kontrol akışı

## Canlı PARDEX Online

Production WebSocket adresi:

```text
wss://pardex-online-production.up.railway.app
```

Railway production servisi `/health` health check ile izlenir. PARDEX istemcisi eski yerel varsayılan `ws://127.0.0.1:8765` ayarını görürse otomatik olarak resmi production servisine yönelir.

Arkadaşlık verilerinin deploy/restart sonrasında korunması için production sunucusunda `PARDEX_SOCIAL_DATA_PATH` kalıcı Railway Volume üzerindeki bir dosyaya yönlendirilmelidir. Mevcut production kurulumu `/data/social.json` kullanır. Ayrıntılar `server/DEPLOYMENT.md` dosyasındadır.

## PARDEX kimliği

Geliştirme aşamasındaki sosyal sistem hesap açma ekranı gerektirmez. PARDEX ilk çalıştırmada cihazda rastgele bir kimlik anahtarı oluşturur; sunucu bu anahtardan anonim ve kalıcı bir `px_...` hesap ID'si türetir.

Kimlik anahtarı sosyal veri dosyasına kaydedilmez. Yerel kimlik dosyası biçim olarak doğrulanır; bozuk bir anahtar algılanırsa PARDEX yeni geçerli bir cihaz kimliği oluşturur. Cihazdaki `user://pardex_identity.cfg` silinir veya yeniden oluşturulursa kullanıcı yeni bir PARDEX hesabı gibi görünür. Bu nedenle uzun vadeli production aşamasında kurtarma kodu veya gerçek hesap/kurtarma sistemi gereklidir.

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

Tüm oda ve sosyal entegrasyon testlerini çalıştırmak için:

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

Sosyal çekirdeğin ana parçaları tamamlandı: kalıcı cihaz kimliği, arkadaşlık, session recovery, oda daveti, bildirim merkezi, presence ve arkadaş odasına doğrudan katılma çalışıyor.

Sıradaki öncelikler:

1. PARDEX kimliği için kurtarma / başka cihaza taşıma akışı.
2. Oyun oturumunu `lobby → launching → in_game → ended` olarak izleyen gerçek game lifecycle.
3. Korsanların Hazinesi Windows exportu hazır olduğunda launcher manifesti, kurulum/güncelleme ve gerçek `OYNA` akışı.
4. Kullanıcı sayısı büyümeden önce dosya tabanlı sosyal depodan SQLite/PostgreSQL gibi daha ölçeklenebilir bir veri katmanına geçiş planı.
