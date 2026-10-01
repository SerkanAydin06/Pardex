# PARDEX'i kendi bilgisayarından açmak

Sunucu senin bilgisayarında çalışır, arkadaşların internetten bağlanır. Ücret, hesap, port açma yok.
Arkadaşların hiçbir ayar yapmaz: PARDEX açılışta senin sunucunun güncel adresini GitHub'dan otomatik okur.

## Kullanım

1. `PARDEX-Sunucu.bat` dosyasına çift tıkla. Tarayıcıda **PARDEX Sunucu Paneli** açılır.
   (İlk seferde Node.js'i kurulum yapmadan `host/bin/node` klasörüne kendisi indirir.)
2. İlk sefer **Ayarlar** bölümünü doldur ve **Kaydet**'e bas:
   - **Korsanların Hazinesi:** oyunun proje klasörü (içinde `project.godot` olan) ya da dışa aktarılmış exe.
     PARDEX klasörüyle yan yana `Korsanlarin-Hazinesi` klasöründeyse kendisi bulur. **Klasör Seç** ile de seçebilirsin.
   - **Godot programı:** proje klasörü kullanılıyorsa Godot'u açtığın .exe (**Dosya Seç**).
   - **GitHub anahtarı:** paneldeki "Anahtar nasıl alınır?" adımlarını izle. Yalnızca bu bilgisayarda saklanır.
3. **Sunucuyu Başlat**'a bas, yeşil **Sunucu açık** yazısını bekle (~10–20 sn).
4. Bitince **Sunucuyu Durdur**. Arkadaşlarının PARDEX'i "sunucu kapalı" görür.

Sunucu açıkken siyah bat penceresini kapatma; panel sekmesini kapatsan da sunucu çalışmaya devam eder
(tekrar görmek için bat dosyasını yeniden aç). Oynarken bilgisayarın uyku moduna geçmemeli.

## Bilmen gerekenler

- Arkadaşlıklar ve profiller `host/data/social.json` dosyasında, senin bilgisayarında durur. Ara sıra yedekle.
- "Yalnızca bu bilgisayarda test et" kutusu tünel açmadan ve adres yayınlamadan yerel deneme yapar.
- Sorun olursa paneldeki **Kayıtlar** bölümünü bana gönder.
- Arkadaşlarının PARDEX'inde Ayarlar → PARDEX Online alanı **boş** kalmalı (boş = otomatik).
