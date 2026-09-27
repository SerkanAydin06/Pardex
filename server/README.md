# PARDEX Online Server

PARDEX launcher istemcilerinin oda/session, sosyal özellikler ve anonim hesap kurtarma akışını yöneten hafif WebSocket sunucusudur.

## Mevcut özellikler

- Kalıcı cihaz tabanlı anonim PARDEX `account_id`
- Hash'lenmiş cihaz alias'larıyla başka bilgisayara hesap taşıma
- Tek kullanımlık recovery code desteği
- Başarılı transferde eski cihaz kimliği ve açık session'ların iptal edilmesi
- Kullanıcı arama
- Arkadaşlık isteği gönderme, kabul, ret ve iptal
- Arkadaş kaldırma
- Presence ve arkadaşın odasına doğrudan katılma
- Süreli oda davetleri
- Arkadaşlık ve hesap eşleme verilerinin disk üzerinde kalıcı saklanması
- Oda oluşturma ve oda koduyla katılma
- Oyuncu listesi, host ve hazır durumu senkronizasyonu
- Kısa bağlantı kopmalarında session recovery
- Oyun başlatma koordinasyonu
- Heartbeat, hello timeout, mesaj boyutu sınırı ve rate limit
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

Varsayılan sosyal/hesap veri dosyası:

```text
server/data/social.json
```

Bu klasör Git tarafından takip edilmez.

## Ortam değişkenleri

```text
HOST=0.0.0.0
PORT=8765
SESSION_GRACE_MS=30000
ROOM_INVITE_TTL_MS=60000
HELLO_TIMEOUT_MS=10000
PARDEX_SOCIAL_DATA_PATH=./data/social.json
PARDEX_VOICE_RELAY_ENABLED=false
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

`/health` yanıtında `accountRecovery: true` recovery-capable sunucuyu belirtir.

## Kimlik modeli

PARDEX ilk çalıştırmada istemcide 256-bit rastgele bir cihaz kimlik anahtarı üretir ve `user://pardex_identity.cfg` içinde saklar. İlk bağlantıda mevcut hesaplarla geriye uyumluluğu korumak için anonim `px_...` hesap kimliği deterministik olarak türetilir.

Sunucu ham cihaz anahtarını kalıcı veri dosyasına yazmaz. Bunun yerine domain-separated SHA-256 ile türetilmiş identity fingerprint/alias değerleri tutulur. Böylece recovery sonrasında farklı bir cihaz anahtarı aynı `account_id` ile güvenli biçimde eşlenebilir.

### Recovery code

Kurtarma kodu istemcide 128-bit rastgele veriyle üretilir ve şu kullanıcı dostu biçimde gösterilir:

```text
PX1-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX
```

Sunucu düz metin kodu saklamaz; yalnız `sha256("pardex-recovery-v1:" + normalized_code)` özeti kalıcı veriye yazılır.

Başarılı kurtarma işlemi atomik olarak şu davranışı uygular:

- Kurtarma hash'i tek kullanımlık olarak temizlenir.
- Yeni cihaz fingerprint'i mevcut hesaba bağlanır.
- Aynı hesaba ait eski identity alias'ları kaldırılır.
- Eski cihazın aktif WebSocket/session kayıtları `4003` ile kapatılır.
- Eski cihaz kimliği daha sonra yeniden bağlanmaya çalışırsa mevcut hesabı tekrar claim edemez.
- Profil adı, arkadaşlıklar ve sosyal hesap ID'si korunur.

İstemci başarılı recovery sonrasında otomatik olarak yeni bir kurtarma kodu üretir. Kurtarma kodu ve ham identity key loglanmamalı veya kullanıcı dışındaki taraflarla paylaşılmamalıdır.

Bu katman e-posta/parola hesabı değildir. Kullanıcı hem eski cihazını hem recovery code'unu kaybederse şu anda otomatik ikinci seviye hesap kurtarma yoktur.

## Recovery veri şeması

`social.json` şeması v2 ile geriye uyumlu olarak genişletilir:

- `accounts`: profil, arkadaşlık ve `recovery_hash`
- `identity_aliases`: hash'lenmiş cihaz fingerprint → `account_id` eşlemesi

Eski v1 hesaplar ilk başarılı bağlantıda kendi ilk identity alias'larını claim eder. Bir hesap alias sahibi olduktan sonra bilinmeyen bir cihaz yalnız legacy deterministik ID üzerinden hesabı ele geçiremez; recovery code gerekir.

## Mevcut protokol

İstemciden sunucuya başlıca mesajlar:

- `hello`
  - normal bağlantıda `identity_key` ve isteğe bağlı `resume_token`
  - recovery bağlantısında `identity_key` + `recovery_code`
- `set_recovery_code`
- `get_social_state`
- `search_users`
- `set_presence`
- `send_friend_request`
- `accept_friend_request`
- `decline_friend_request`
- `cancel_friend_request`
- `remove_friend`
- `send_room_invite`
- `accept_room_invite`
- `decline_room_invite`
- `join_friend_room`
- `create_room`
- `join_room`
- `leave_room`
- `set_ready`
- `start_game`
- `launch_failed`
- `ping`

Sunucudan istemciye başlıca mesajlar:

- `welcome`
  - `recovered`
  - `recovery_enabled`
- `recovery_code_saved`
- `social_state`
- `user_search_results`
- `social_notice`
- `presence_state`
- `room_invite`
- `room_invite_closed`
- `room_state`
- `game_start`
- `left_room`
- `error`
- `pong`

## Otomatik test

`npm test` şu entegrasyon paketlerini çalıştırır:

1. Oda/session testi: kalıcı kimlik → oda oluşturma → katılma → reconnect recovery → ready → oyun başlatma → rollback → session expiry.
2. Sosyal test: kullanıcı arama → arkadaşlık isteği → kabul → server restart → persistence → arkadaş kaldırma.
3. Oda daveti testi.
4. Presence / friend-join testi.
5. Hardening testi.
6. Account recovery testi: arkadaşlığı olan hesabı yeni cihaz kimliğine taşıma → eski canlı session'ın kapanması → tek kullanımlık kod replay reddi → plaintext secret'ların diske yazılmaması → server restart → eski cihazın reddi → yeni cihazın aynı hesaba dönmesi.

GitHub Actions ayrıca Node.js sözdizimini, Docker image build'ini ve oluşturulan container'ın gerçekten açılıp `/health` yanıtı vermesini doğrular.

## Production deploy

Railway ayarları ve kalıcı Volume kurulumu için:

```text
server/DEPLOYMENT.md
```

Oda/session verileri RAM'de tutulur ve servis restartında temizlenir. Arkadaşlık, identity alias ve recovery bilgileri ise yapılandırılmış kalıcı dosyada saklanır.
