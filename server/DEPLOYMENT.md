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

PARDEX > Ayarlar > PARDEX Online alanında bu `wss://` adresi ile test edilir. Üretim adresi kesinleşince istemcinin varsayılan adresi bu domaine sabitlenecek ve son kullanıcıdan sunucu adresi istenmeyecek.

## Canlı doğrulama

Deploy sonrası:

1. `https://<domain>/health` 2xx dönmeli.
2. PARDEX üst durum etiketi `ÇEVRİMİÇİ` olmalı.
3. Bir istemci oda oluşturmalı ve 5 karakterlik kod almalı.
4. Farklı internet bağlantısındaki ikinci istemci aynı kodla katılmalı.
5. Hazır durumu iki tarafta da eş zamanlı görünmeli.

## Güvenlik notu

Canlı kullanımda `wss://` kullanılmalıdır. `ws://` yalnız yerel geliştirme/LAN testleri içindir.
