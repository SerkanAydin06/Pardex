# PARDEX

PARDEX, VEX, Korsanların Hazinesi ve Fırtına Vadisi gibi oyunları tek uygulamada toplayacak Godot 4.7 tabanlı game hub / launcher projesidir.

## v0.1.0

- Kütüphane ana ekranı
- VEX, Korsanların Hazinesi ve Fırtına Vadisi kartları
- Yerel oyun yolu algılama altyapısı
- Oyun executable'ını başlatabilen OYNA davranışı
- Arkadaşlar / Odalar / Ayarlar için PARDEX Online'a hazır navigasyon iskeleti
- 1920x1080 tabanlı responsive Control arayüzü

## Yerel oyun yolları

PARDEX ilk açılışta `user://pardex_games.cfg` oluşturur. Örnek:

```ini
[games]
vex="C:/Games/VEX/VEX.exe"
korsanlar="C:/Games/Korsanlar/KorsanlarinHazinesi.exe"
firtina="C:/Games/FirtinaVadisi/FirtinaVadisi.exe"
```

Yol tanımlı ve dosya mevcutsa kartın düğmesi `OYNA` olur.

## Sıradaki aşama

İlk online entegrasyon Korsanların Hazinesi ile yapılacak. PARDEX Online katmanı hesap, arkadaş, oda ve session bilgisini yönetecek; oyun mevcut NetworkManager yapısına bu oturum üzerinden bağlanacak.
