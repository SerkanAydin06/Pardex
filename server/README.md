# PARDEX Online Server

PARDEX launcher istemcilerinin oda oluşturma, oda koduyla katılma, oyuncu listesi ve hazır durumunu senkronize eden hafif WebSocket sunucusudur.

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

PARDEX > Ayarlar > PARDEX Online alanına bu adres yazıldığında aynı bilgisayardaki istemci yerel sunucuya bağlanır.

## Docker ile çalıştırma

`server` klasöründe:

```bash
docker build -t pardex-online .
docker run --rm -p 8765:8765 pardex-online
```

Sağlık kontrolü:

```text
http://127.0.0.1:8765/health
```

## Farklı bilgisayarlarda test

Aynı ağ içindeki başka bir bilgisayar, sunucuyu çalıştıran bilgisayarın LAN IP adresini kullanabilir:

```text
ws://192.168.x.x:8765
```

Gerçek farklı internet ağları için bu sunucu bir VPS / bulut sunucusunda yayınlanacak. Yayın ortamında TLS ters proxy üzerinden `wss://...` adresi kullanılacak; son kullanıcı sunucu adresi girmeyecek.

## Mevcut protokol

İstemciden sunucuya:

- `hello`
- `create_room`
- `join_room`
- `leave_room`
- `set_ready`
- `ping`

Sunucudan istemciye:

- `welcome`
- `room_state`
- `left_room`
- `error`
- `pong`

## Otomatik test

`npm test`, iki ayrı WebSocket istemcisi açarak şu zinciri doğrular:

1. İki istemci bağlanır.
2. Birinci istemci oda oluşturur.
3. İkinci istemci oda koduyla katılır.
4. İkinci istemci hazır olur.
5. Oda durumu iki istemciye de aynı şekilde yayınlanır.

GitHub Actions bu testi ve Docker image build kontrolünü sunucu değişikliklerinde otomatik çalıştırır.

Şimdilik oturumlar sunucu belleğinde tutulur. Sunucu yeniden başlatılırsa odalar silinir. Hesap, kalıcı arkadaş listesi ve veritabanı sonraki katmandır.
