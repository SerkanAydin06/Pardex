# PARDEX yapılacaklar

Yalnızca henüz yapılmamış işler. Biten maddeyi listeden sil.

## Senin yapman gerekenler
- [ ] Sunucu bilgisayarına Cloudflare WARP (1.1.1.1) kur; `PARDEX-Ag-Testi.bat` ile dağıtım sunucusuna ulaşıldığını, panelde adresin yayınlandığını ve PARDEX'in otomatik bağlandığını doğrula.
- [ ] Alan adı al (ör. Cloudflare Registrar) ve `pardex-distribution` Worker'ını ona bağla: internet sağlayıcısı `workers.dev`, `pages.dev` ve `r2.dev` adreslerini engelliyor. Sonra panelin yayın adresini ve `pardex-distribution.json` adresini yeni alan adıyla değiştir.
- [ ] İkinci bir bilgisayardan (başka internet) PARDEX'e girip çevrimiçi görünürlüğü dene.
- [ ] Windows'ta elle dene: tepsi simgesi ve görev çubuğu yanıp sönmesi.
- [ ] İlk uygulama güncellemesini R2 kanalından (`channel.json`) uçtan uca dene.
- [ ] Sabit tünel istersen: Cloudflare'de tünel ve adresleri oluştur, sunucu panelinde kaydet.

## Geliştirme
- [ ] Dışa aktarılan `PARDEX.exe` için uygulama simgesi (`export_presets.cfg` → `application/icon` boş).
- [ ] Bildirim seslerini Ayarlar'dan kapatma seçeneği.
- [ ] Sesli sohbet kapalı; istenirse baştan tasarlanmalı.
- [ ] VEX ve Fırtına Vadisi için oyun entegrasyonu (şimdilik "yakında").
- [ ] Favoriler, istek listesi ve oynama süresi yalnız bu bilgisayarda; sunucuya eşitleme yok.
- [ ] Seviye, rozet ve Plus yer tutucu; gerçek karşılıkları yok.
