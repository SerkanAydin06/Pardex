# PARDEX Online Server

PARDEX launcher istemcilerinin oda/session ve sosyal özelliklerini yöneten hafif WebSocket sunucusudur.

## Mevcut özellikler

- Kalıcı cihaz tabanlı anonim PARDEX `account_id`
- Kullanıcı arama
- Arkadaşlık isteği gönderme, kabul, ret ve iptal
- Arkadaş kaldırma
- Çevrimiçi / çevrimdışı durum bilgisi
- Arkadaşlıkların disk üzerinde kalıcı saklanması
- Oda oluşturma ve oda koduyla katılma
- Oyuncu listesi, host ve hazır durumu senkronizasyonu
- Kısa bağlantı kopmalarında session recovery
- Oyun başlatma koordinasyonu
- Heartbeat, mesaj boyutu sınırı ve rate limit
- Docker ve `/health` desteği

## Yerel geliştirme

Node.js 20+ ile:

```bash
cd server
npm install
npm start
```

Varsayılan adres:

```text
ws://127.0.0.1:8765
```

Varsayılan sosyal veri dosyası:

```text
server/data/social.json
```

Bu klasör Git tarafından takip edilmez.

## Ortam değişkenleri

```text
HOST=0.0.0.0
PORT=8765
SESSION_GRACE_MS=30000
PARDEX_SOCIAL_DATA_PATH=./data/social.json
KORSAN_GAME_SERVER_URL=
```

Production ortamında `PARDEX_SOCIAL_DATA_PATH` mutlaka kalıcı disk/volume üzerinde bir konuma verilmelidir.

## Docker ile çalıştırma

`server` klasöründe:

```bash
docker build -t pardex-online .
docker run --rm -p 8765:8765 pardex-online
```

Kalıcı sosyal veriyle örnek:

```bash
docker run --rm -p 8765:8765 \
  -v pardex-social:/data \
  -e PARDEX_SOCIAL_DATA_PATH=/data/social.json \
  pardex-online
```

Sağlık kontrolü:

```text
http://127.0.0.1:8765/health
```

## Kimlik modeli

PARDEX ilk çalıştırmada istemcide 256-bit rastgele bir cihaz kimlik anahtarı üretir ve `user://pardex_identity.cfg` içinde saklar. Sunucu bu anahtardan deterministik bir anonim `px_...` hesap kimliği türetir.

Sunucunun sosyal veri dosyasında cihaz anahtarı tutulmaz. Bu sistem geliştirme ve erken test dönemi içindir; cihazdaki kimlik dosyası silinirse kullanıcı yeni bir hesap gibi görünür. Gerçek hesap kurtarma, e-posta/parola veya harici kimlik sağlayıcısı daha sonraki production hesap katmanının konusudur.

## Mevcut protokol

İstemciden sunucuya başlıca mesajlar:

- `hello`
- `get_social_state`
- `search_users`
- `send_friend_request`
- `accept_friend_request`
- `decline_friend_request`
- `cancel_friend_request`
- `remove_friend`
- `create_room`
- `join_room`
- `leave_room`
- `set_ready`
- `start_game`
- `launch_failed`
- `ping`

Sunucudan istemciye başlıca mesajlar:

- `welcome`
- `social_state`
- `user_search_results`
- `social_notice`
- `room_state`
- `game_start`
- `left_room`
- `error`
- `pong`

## Otomatik test

`npm test` iki ayrı entegrasyon testini çalıştırır:

1. Oda testi: kalıcı kimlik → oda oluşturma → katılma → reconnect recovery → ready → oyun başlatma → rollback → session expiry.
2. Sosyal test: kalıcı kimlik → kullanıcı arama → arkadaşlık isteği → kabul → sunucuyu yeniden başlatma → arkadaşlığın diskten geri yüklenmesi → arkadaş kaldırma.

GitHub Actions ayrıca Node.js sözdizimini, Docker image build'ini ve oluşturulan container'ın gerçekten açılıp `/health` yanıtı vermesini doğrular.

## Production deploy

Railway ayarları ve kalıcı Volume kurulumu için:

```text
server/DEPLOYMENT.md
```

Oda/session verileri şimdilik RAM'de tutulur ve servis restartında temizlenir. Arkadaşlık verileri ise yapılandırılmış kalıcı dosyada saklanabilir.
