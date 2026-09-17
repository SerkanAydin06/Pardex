# PARDEX

PARDEX, VEX, Korsanların Hazinesi ve Fırtına Vadisi gibi oyunları tek uygulamada toplayacak Godot 4.7 tabanlı game hub / launcher projesidir.

## Mevcut durum

- 1920×1080 tam ekran ana uygulama
- Kütüphane ekranı
- VEX, Korsanların Hazinesi ve Fırtına Vadisi kartları
- Ayrı Arkadaşlar / Odalar / Ayarlar ekranları
- Yerel profil adı kaydı
- Uygulama içinden güvenli çıkış
- Godot tarafında `PardexOnline` WebSocket istemcisi
- Otomatik reconnect ve heartbeat bağlantı kontrolü
- Node.js tabanlı PARDEX Online oda sunucusu
- Oda oluşturma ve 5 karakterlik oda kodu
- Oda koduyla katılma
- Oyuncu listesi ve host bilgisi
- Hazır / hazır değil senkronizasyonu
- Odadan çıkma ve host devri
- Ayarlardan geliştirme sunucusu adresi değiştirme
- Sunucuda mesaj boyutu ve temel hız sınırı koruması
- Graceful shutdown desteği
- Docker ile deploy edilebilir sunucu paketi
- GitHub Actions üzerinde sunucu sözdizimi, iki istemcili smoke test ve Docker build kontrolü
- GitHub Actions üzerinde Godot 4.7.2 sahne/script doğrulaması

## Oyunların durumu

Oyunlar hâlâ geliştirme aşamasında olduğu için şu anda Windows `.exe` exportları PARDEX'e bağlanmıyor. Export, kurulum, güncelleme ve `OYNA` akışı oyunlar yeterince hazır olduğunda eklenecek.

İlk gerçek oyun entegrasyonu Korsanların Hazinesi ile yapılacak.

## PARDEX Online geliştirme testi

Yerel sunucuyu çalıştırmak için:

```bash
cd server
npm install
npm start
```

Varsayılan istemci adresi:

```text
ws://127.0.0.1:8765
```

Aynı ağdaki başka bir bilgisayar sunucu bilgisayarının LAN IP adresini kullanabilir.

## İnternet dağıtımı

PARDEX Online sunucusu `server/` klasöründen Docker ile dağıtıma hazırdır. Railway için ayrıntılı kurulum notları:

```text
server/DEPLOYMENT.md
```

Canlı sunucu yayınlandığında istemci `wss://` adresine bağlanacak. Üretim adresi kesinleşince son kullanıcıdan sunucu adresi istenmeyecek; PARDEX doğrudan resmi online servise bağlanacak.

## Sıradaki teknik aşama

PARDEX Online sunucusunu internette yayınlamak ve iki farklı ağdaki iki PARDEX istemcisini aynı oda koduyla buluşturmak. Bu doğrulandıktan sonra Korsanların Hazinesi'nin mevcut multiplayer katmanı PARDEX oturum bilgisine bağlanacak.
