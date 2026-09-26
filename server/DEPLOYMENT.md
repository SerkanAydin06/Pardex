# PARDEX Online — Railway Deployment

Bu servis uzun süre çalışan bir WebSocket sunucusudur. Railway'de tek servis olarak `server/` klasöründen deploy edilir.

## Railway ayarları

- Source: `SerkanAydin06/Pardex`
- Root Directory: `/server`
- Builder: Dockerfile otomatik algılama
- Health Check Path: `/health`
- Public Networking: açık
- PORT: Railway tarafından sağlanan `PORT` ortam değişkeni kullanılır; ayrıca sabit port tanımlamaya gerek yoktur.

`server.js` zaten `process.env.PORT` ve `process.env.HOST` değerlerini kullanır. Dockerfile da `server/` kökünden bağımsız çalışacak şekilde hazırdır.

## Kalıcı sosyal veri

PARDEX arkadaşlıkları ve kullanıcı profilleri varsayılan olarak JSON dosyasında tutulur. Railway servis dosya sistemi deploy/restart sırasında kalıcı kabul edilmemelidir. Arkadaş listesinin kaybolmaması için production servisine bir **Railway Volume** bağlanmalıdır.

Önerilen yapı:

1. Railway servisinde yeni bir Volume oluştur.
2. Volume mount path değerini `/data` yap.
3. Servis değişkenlerine şunu ekle:

```text
PARDEX_SOCIAL_DATA_PATH=/data/social.json
```

4. Deploy sonrası `/health` yanıtındaki `socialDataPathConfigured` alanı `true` olmalı.

Yerel geliştirmede varsayılan yol `server/data/social.json` olarak kullanılabilir. `server/data/` Git tarafından takip edilmez.

> Not: Mevcut kimlik sistemi geliştirme aşaması için cihaz tabanlı anonim PARDEX kimliğidir. Kimlik anahtarı kullanıcının cihazındaki `user://pardex_identity.cfg` dosyasında tutulur ve sunucu sosyal veri dosyasına kaydedilmez. Bu dosya silinirse o cihaz yeni bir PARDEX hesabı gibi görünür. E-posta/parola veya hesap kurtarma sistemi daha sonraki production hesap katmanında eklenecektir.

## Session recovery

Kısa bağlantı kopmalarında oyuncunun oda üyeliği, host rolü ve hazır durumu varsayılan olarak 30 saniye korunur. Süre şu değişkenle ayarlanabilir:

```text
SESSION_GRACE_MS=30000
```

## Bağlantı adresi

Railway public domain oluşturduktan sonra HTTPS adresinin WebSocket karşılığı PARDEX istemcisinde kullanılır.

Örnek:

```text
https://pardex-online-production.up.railway.app
```

PARDEX WebSocket adresi:

```text
wss://pardex-online-production.up.railway.app
```

PARDEX > Ayarlar > PARDEX Online alanında bu `wss://` adresi ile test edilir. Production kullanımında son kullanıcıdan sunucu adresi istenmez; istemci resmi servise doğrudan bağlanır.

## Canlı doğrulama

Deploy sonrası:

1. `https://<domain>/health` 2xx dönmeli.
2. PARDEX üst durum etiketi `ÇEVRİMİÇİ` olmalı.
3. İki farklı PARDEX kurulumu farklı kalıcı `account_id` almalı.
4. Bir kullanıcı diğerini arayıp arkadaşlık isteği gönderebilmeli ve kabul edebilmelidir.
5. Servis yeniden deploy edildiğinde Volume üzerindeki arkadaşlıklar korunmalıdır.
6. Bir istemci oda oluşturmalı ve 5 karakterlik kod almalı.
7. İkinci istemci aynı kodla katılmalı; hazır durumu iki tarafta eş zamanlı görünmelidir.
8. Kısa bağlantı kopmasında istemci aynı oda/host durumuna geri dönebilmelidir.

## Güvenlik notu

Canlı kullanımda `wss://` kullanılmalıdır. `ws://` yalnız yerel geliştirme/LAN testleri içindir. Yerel cihaz kimliği bir parola değildir ve kullanıcıya gösterilmemelidir; yalnızca PARDEX istemcisi ile sunucu arasındaki güvenli `wss://` bağlantısında kullanılır.
