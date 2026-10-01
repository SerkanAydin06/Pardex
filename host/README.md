# PARDEX'i kendi bilgisayarından açmak

Sunucu senin bilgisayarında çalışır, arkadaşların internetten bağlanır. Ücret, hesap, port açma yok.
Arkadaşların hiçbir ayar yapmaz: PARDEX açılışta senin sunucunun güncel adresini GitHub'dan otomatik okur.

## Kullanım

1. **`PARDEX-Sunucu-Paneli.vbs`** dosyasına çift tıkla. **PARDEX Sunucu Paneli** kendi penceresinde açılır,
   siyah pencere çıkmaz. (İlk seferde Node.js'i `host/bin/node` klasörüne indirirken bir kez görünür pencere açılır.)
   Masaüstüne kısayol: dosyaya sağ tık → Gönder → Masaüstü (kısayol oluştur).
2. İlk sefer **Ayarlar** bölümünü doldur ve **Kaydet**'e bas:
   - **Korsanların Hazinesi:** oyunun proje klasörü (içinde `project.godot` olan) ya da dışa aktarılmış exe.
     PARDEX klasörüyle yan yana `Korsanlarin-Hazinesi` klasöründeyse kendisi bulur. **Klasör Seç** ile de seçebilirsin.
   - **Godot programı:** proje klasörü kullanılıyorsa Godot'u açtığın .exe (**Dosya Seç**).
   - **GitHub anahtarı:** https://github.com/settings/tokens/new?scopes=public_repo&description=PARDEX%20Sunucu bağlantısını aç, en alttaki **Generate token**'a bas,
     çıkan `ghp_...` anahtarını panele yapıştır. Yalnızca bu bilgisayarda saklanır.
3. **Sunucuyu Başlat**'a bas, yeşil **Sunucu açık** yazısını bekle (~10–20 sn).
4. Bitince **Sunucuyu Durdur**. Arkadaşlarının PARDEX'i "sunucu kapalı" görür.

Panel penceresini kapatsan da açık sunucu arka planda çalışır; paneli tekrar açmak için .vbs dosyasına yeniden çift tıkla.
Tamamen kapatmak için panelde **Paneli Kapat**. Sunucu kapalıyken panel penceresini kapatırsan arka plan da kendiliğinden kapanır.
Oynarken bilgisayarın uyku moduna geçmemeli. (Sorun ararken `PARDEX-Sunucu.bat` ile görünür pencerede de açabilirsin.)

## Bilmen gerekenler

- Arkadaşlıklar ve profiller `host/data/social.json` dosyasında, senin bilgisayarında durur. Ara sıra yedekle.
- "Yalnızca bu bilgisayarda test et" kutusu tünel açmadan ve adres yayınlamadan yerel deneme yapar.
- Sorun olursa paneldeki **Kayıtlar** bölümünü bana gönder.
- Arkadaşlarının PARDEX'inde Ayarlar → PARDEX Online alanı **boş** kalmalı (boş = otomatik).
