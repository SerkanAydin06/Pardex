# PARDEX'i kendi bilgisayarından açmak

Sunucu senin bilgisayarında çalışır, arkadaşların internetten bağlanır. Ücret, hesap, port açma yok.
Arkadaşların hiçbir ayar yapmaz: PARDEX açılışta senin sunucunun güncel adresini GitHub'dan otomatik okur.

## İlk kurulum (bir kere)

1. Repoyu bilgisayarına indir (GitHub Desktop ya da `git clone`).
2. Korsanların Hazinesi'ni Godot'tan **Windows Desktop** olarak dışa aktar
   (`build/KorsanlarinHazinesi.exe`). PARDEX reposuyla yan yana `Korsanlarin-Hazinesi` klasöründeyse otomatik bulunur;
   değilse ilk açılışta yolu sorar.
3. `PARDEX-Sunucu.bat` dosyasına çift tıkla.
   - Node.js yoksa kendisi kurar; kurulum bitince dosyayı tekrar aç.
   - Senden bir kere **GitHub anahtarı** ister. Ekrandaki 4 adımı izle:
     https://github.com/settings/personal-access-tokens/new →
     *Only select repositories: SerkanAydin06/Pardex* → *Contents: Read and write* → *Generate token*.
     Anahtar yalnızca bu bilgisayarda (`host/pardex_host.local.json`) saklanır, GitHub'a yüklenmez.

## Her oyun gecesi

1. `PARDEX-Sunucu.bat` dosyasına çift tıkla, **SUNUCU AÇIK** yazısını bekle (~10 sn).
2. Arkadaşlarına "açtım" de. PARDEX'leri açıksa en geç 1 dakika içinde kendiliğinden bağlanırlar.
3. Bitince pencerede **Ctrl+C**'ye bas. Sunucu kapanır ve arkadaşlarının PARDEX'i "sunucu kapalı" görür.

Bilgisayar uyku moduna geçerse sunucu durur; oynarken uyku modunu kapat.

## Bilmen gerekenler

- Arkadaşlıklar ve profiller `host/data/social.json` dosyasında, senin bilgisayarında durur. Ara sıra yedekle.
- Ayarları sıfırlamak (GitHub anahtarını ya da oyun yolunu değiştirmek) için `host/pardex_host.local.json` dosyasını sil.
- Yalnızca kendi bilgisayarında test etmek için: `PARDEX-Sunucu.bat --yerel` (tünel açmaz, adres yayınlamaz).
- Arkadaşlarının PARDEX'inde Ayarlar → PARDEX Online alanı **boş** kalmalı (boş = otomatik).
