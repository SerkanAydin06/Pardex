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

## Farklı bilgisayarlarda test

Aynı ağ içindeki başka bir bilgisayar, sunucuyu çalıştıran bilgisayarın LAN IP adresini kullanabilir:

```text
ws://192.168.x.x:8765
```

Gerçek farklı internet ağları için bu sunucu daha sonra bir VPS / bulut sunucusunda yayınlanacak ve PARDEX içinde `wss://...` adresi sabitlenecek.

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

Şimdilik oturumlar sunucu belleğinde tutulur. Sunucu yeniden başlatılırsa odalar silinir. Hesap, kalıcı arkadaş listesi ve veritabanı sonraki katmandır.
