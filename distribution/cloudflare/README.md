# Cloudflare R2 dağıtımı

R2 oyun ZIP'lerini ve Pardex kurulum EXE'sini saklar. Worker bunları sabit HTTPS
`workers.dev` adresinden sunar; alan adı veya GitHub hesabı kullanıcılar için gerekmez.
Oyun/sosyal sunucusu ayrı olarak ev bilgisayarında çalışır. R2 onu çalıştırmaz.
`r2.dev` geliştirme adresini dağıtılan EXE'ye koymayın; üretim için tasarlanmamıştır.

## Bir defalık kurulum

Cloudflare hesabında R2'yi etkinleştirin. Ücretsiz kota sınırsız değildir; R2 etkinleştirme
faturalandırma bilgisi isteyebilir. Ücretli Workers planı bu kurulum için gerekli değildir.
Node.js ve resmi Wrangler CLI ile bu dizinde:

```sh
npx wrangler login
npx wrangler r2 bucket create pardex-releases
npx wrangler secret put PUBLISH_TOKEN
npx wrangler deploy
```

Mevcut bucket varsa yeniden oluşturmayın. `PUBLISH_TOKEN` için parola yöneticisinde
üretilmiş en az 32 karakterlik rastgele değeri CLI'nin gizli girişine yazın ve ev
sunucusunun yayınlama anahtarına da aynı değeri girin. Anahtarı repoya veya sohbete
koymayın. R2 bucket'ının public erişimini açmayın; Worker yalnızca izin verilen
`channel.json`, `online.json` ve hash adlı paketleri sunar.

Deploy çıktısındaki gerçek HTTPS Worker adresini kaydedin. Bu adres tüm Windows
paketlerinde `-DistributionUrl` ve yayınlama komutlarında `--url` olarak aynı olmalıdır.
Worker adını/Cloudflare hesabını sonradan değiştirirseniz dağıtılmış EXE'lerdeki adres
kendiliğinden değişmez. İlk yayında `channel.json` paketler hazır olana kadar 404 döner;
`online.json` ev sunucusu ilk adresini yayınlayana kadar 404 döner.

## Yeni sürüm veya oyun yayınlama

Windows paketlerini üst dizindeki dağıtım yönergesiyle üretin. AWS CLI v2 kurun;
Cloudflare R2 panelinden yalnızca `pardex-releases` bucket'ına Object Read & Write
izni olan S3 kimlik bilgilerini yerel AWS profilinize kaydedin (`aws configure
--profile pardex-r2`). Cloudflare hesap kimliği gizli anahtar değildir. Profilinizi
`AWS_PROFILE=pardex-r2` ortam değişkeniyle seçin (PowerShell:
`$env:AWS_PROFILE = 'pardex-r2'`). Depo kökünde:

```sh
python tools/publish_release.py --spec release.local.json --url https://GERCEK-WORKER-ADRESI --output distribution/public
python tools/upload_r2.py --account-id CLOUDFLARE_HESAP_KIMLIGI --url https://GERCEK-WORKER-ADRESI
```

`release.local.json` örneği (Git'e eklenmez; `cover`, `banner`, `genres`,
`description` ve `players` isteğe bağlıdır):

```json
{
  "games": [{
    "id": "ornek-oyun",
    "title": "Örnek Oyun",
    "version": "1.0.0",
    "directory": "C:/Godot Projeleri/OrnekOyun/export",
    "executable": "OrnekOyun.exe",
    "description": "Kısa tanıtım cümlesi.",
    "players": "Tek oyunculu",
    "genres": ["Macera", "Bulmaca"],
    "cover": "C:/Godot Projeleri/OrnekOyun/kapak.png",
    "banner": "C:/Godot Projeleri/OrnekOyun/afis.png"
  }]
}
```

Kapak dikey kart görseli, afiş mağazanın geniş üst görselidir; PNG, JPG veya WebP,
en çok 8 MB. En çok 4 tür yazılabilir. PARDEX görselleri arka planda indirip doğrular.

Yükleyici tüm dosyaların SHA-256 ve boyutunu önce kontrol eder. AWS CLI büyük dosyaları
multipart yükler; paket yüklemesi başarısızsa katalog değiştirilmez. Paketlerden sonra
katalog yayınlanır. Eski paketler silinmez, `online.json` üzerine yazılmaz. Aynı anda
iki yayıncı çalıştırmayın; doğrulanan yerel dosyaları yükleme sırasında değiştirmeyin.

Ev sunucusu panelindeki yayınlama URL'si: `https://GERCEK-WORKER-ADRESI/online.json`.
Bu PUT uç noktası yalnızca `PUBLISH_TOKEN` ile adres günceller; oyun yüklemeye izin vermez.
Kontrol: gerçek adreste `/channel.json` dosyasını ve bir paket URL'sini indirin;
ev sunucusunu başlatıp `/online.json` içindeki `wss://` adresini doğrulayın. Son olarak
Windows'ta eski sürümden güncelleme ve yeni oyun indirme denemesi yapın.

R2 Standard ücretsiz kotaları ve Workers Free istek sınırlarını panelden izleyin.
Eski büyük paketler de depolama tüketir; bütçe uyarısı bir harcama kesicisi değildir.

Resmi kaynaklar:
- https://developers.cloudflare.com/r2/pricing/
- https://developers.cloudflare.com/workers/platform/limits/
- https://developers.cloudflare.com/r2/examples/aws/aws-cli/
