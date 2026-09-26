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
- Kullanıcı arama ve gerçek arkadaşlık sistemi
- Arkadaşlık isteği gönderme / kabul / ret / iptal
- Arkadaş kaldırma ve online/offline durumu
- Arkadaşlık verilerinin sunucuda kalıcı dosyaya yazılması
- Node.js tabanlı PARDEX Online oda ve sosyal sunucusu
- Oda oluşturma ve 5 karakterlik oda kodu
- Oda koduyla katılma
- Oyuncu listesi, host bilgisi ve hazır durumu senkronizasyonu
- Odadan çıkma ve host devri
- Ayarlardan geliştirme sunucusu adresi değiştirme
- Sunucuda mesaj boyutu ve temel hız sınırı koruması
- Graceful shutdown desteği
- Docker ile deploy edilebilir sunucu paketi
- Railway üzerinde çalışan production PARDEX Online servisi
- GitHub Actions üzerinde oda + sosyal WebSocket smoke testleri
- GitHub Actions üzerinde Docker build ve gerçek container `/health` kontrolü
- GitHub Actions üzerinde Godot 4.7.2 sahne/script doğrulaması
- Canlı `wss://` endpoint'e karşı production smoke test altyapısı

## Canlı PARDEX Online

Production WebSocket adresi:

```text
wss://pardex-online-production.up.railway.app
```

Railway production servisi `/health` health check ile izlenir. PARDEX istemcisi eski yerel varsayılan `ws://127.0.0.1:8765` ayarını görürse otomatik olarak resmi production servisine yönelir.

Arkadaşlık verilerinin deploy/restart sonrasında korunması için production sunucusunda `PARDEX_SOCIAL_DATA_PATH` kalıcı Railway Volume üzerindeki bir dosyaya yönlendirilmelidir. Ayrıntılar `server/DEPLOYMENT.md` dosyasındadır.

## PARDEX kimliği

Geliştirme aşamasındaki sosyal sistem hesap açma ekranı gerektirmez. PARDEX ilk çalıştırmada cihazda rastgele bir kimlik anahtarı oluşturur; sunucu bu anahtardan anonim ve kalıcı bir `px_...` hesap ID'si türetir.

Kimlik anahtarı sosyal veri dosyasına kaydedilmez. Cihazdaki `user://pardex_identity.cfg` silinirse kullanıcı yeni bir PARDEX hesabı gibi görünür. E-posta/parola, hesap kurtarma veya harici kimlik sağlayıcısı daha sonraki production hesap aşamasında eklenecektir.

## Oyunların durumu

Oyunlar hâlâ geliştirme aşamasında olduğu için şu anda Windows `.exe` exportları PARDEX'e bağlanmıyor. Export, kurulum, güncelleme ve gerçek `OYNA` akışı oyunlardan biri yeterince hazır olduğunda eklenecek.

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

Aynı ağdaki başka bir bilgisayar sunucu bilgisayarının LAN IP adresini kullanabilir. Production kullanımında son kullanıcı sunucu adresi girmeyecek; PARDEX doğrudan resmi online servise bağlanır.

## İnternet dağıtımı

PARDEX Online sunucusu `server/` klasöründen Docker ile dağıtıma hazırdır. Railway için ayrıntılı kurulum ve kalıcı sosyal veri notları:

```text
server/DEPLOYMENT.md
```

## Sıradaki teknik aşama

Oyunlar oynanabilir export seviyesine gelene kadar PARDEX tarafında sosyal ve launcher çekirdeği geliştirilecektir. Sıradaki uygun katmanlar; arkadaşlardan oda daveti, bildirim sistemi, profil/presence zenginleştirmesi ve daha sonra gerçek hesap kurtarma altyapısıdır.

Oyunlardan biri hazır olduğunda mevcut oda/session altyapısı kullanılarak `OYNA` → oyun açılışı → aynı multiplayer oturumuna otomatik geçiş akışı bağlanacaktır.
