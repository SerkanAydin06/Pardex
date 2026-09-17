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
- Railway üzerinde çalışan production PARDEX Online servisi
- GitHub Actions üzerinde sunucu sözdizimi, iki istemcili smoke test ve Docker build kontrolü
- GitHub Actions üzerinde Godot 4.7.2 sahne/script doğrulaması
- Canlı `wss://` endpoint'e karşı iki istemcili production smoke test

## Canlı PARDEX Online

Production WebSocket adresi:

```text
wss://pardex-online-production.up.railway.app
```

Railway production servisi `/health` health check ile izlenir. PARDEX istemcisi eski yerel varsayılan `ws://127.0.0.1:8765` ayarını görürse otomatik olarak resmi production servisine yönelir.

## Oyunların durumu

Oyunlar hâlâ geliştirme aşamasında olduğu için şu anda Windows `.exe` exportları PARDEX'e bağlanmıyor. Export, kurulum, güncelleme ve `OYNA` akışı oyunlar yeterince hazır olduğunda eklenecek.

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

Aynı ağdaki başka bir bilgisayar sunucu bilgisayarının LAN IP adresini kullanabilir. Production kullanımında son kullanıcı sunucu adresi girmeyecek; PARDEX doğrudan resmi online servise bağlanır.

## İnternet dağıtımı

PARDEX Online sunucusu `server/` klasöründen Docker ile dağıtıma hazırdır. Railway için ayrıntılı kurulum notları:

```text
server/DEPLOYMENT.md
```

## Sıradaki teknik aşama

Canlı PARDEX oda/session altyapısını Korsanların Hazinesi'nin mevcut multiplayer katmanına bağlamak. Hedef, PARDEX'te aynı odaya giren oyuncuların oyunu açtıklarında aynı Korsanların Hazinesi oturumuna otomatik aktarılmasıdır.
