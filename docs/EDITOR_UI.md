# Godot'ta PARDEX sayfalarını düzenlemek

`scenes/main.tscn` dosyasını aç. Sahne ağacındaki **EditorPreview** düğümünü
seç; Inspector → **Preview Page** alanından Mağaza, Kütüphane, Arkadaşlar,
Mesajlar, Profil veya Ayarlar'ı seç. Seçim yalnızca editör önizlemesini değiştirir.
Uygulama çalışınca normal sekme geçişleri kullanılır.

Sayfa içindeki düğümleri düzenlemek için ilgili `scenes/pages/*_page.tscn`
dosyasını doğrudan aç. Bu sahnelerin bağımsız düzenleme alanı 1440 × 900'dür;
uygulama içinde Container'lar kullanılabilir alana göre yeniden yerleştirir.

Ortak tema `themes/pardex_theme.tres` dosyasındadır. Sabit başlıklar, paneller,
kütüphane/profil sayaçlarının ikonları ve açıklamaları, hızlı başlat düğmeleri
ve profil hesap satırları sahne düğümleridir. Kod bunları silip yeniden üretmez;
yalnızca isim, sayı, tarih, kurulum durumu gibi değişken verileri günceller.

Oyun kartlarının ve canlı sosyal listelerin tekrar eden düzenleri
`scenes/ui/` altındadır: `library_game_card.tscn`, `library_list_row.tscn`,
`store_featured_card.tscn`, `store_new_card.tscn`, `quick_launch_row.tscn`,
`friend_row.tscn`, `conversation_row.tscn`, `chat_bubble.tscn`.
İçerikler oyun çalışırken gerçek katalog, hesap ve sunucu verisinden doldurulur.
Editördeki örnek içerikler canlı kullanıcı verisi değildir.

Eski sayfa üretme aracı kaldırıldı. Sayfalar doğrudan `.tscn` dosyalarından
düzenlenir; kaynak sahneleri yeniden üretmek gerekmez.

## Logo ışık efektleri

Ana sahnedeki `Root/Body/Sidebar/SidebarColumn/BrandHeader/BrandMargin/Brand/Logo` düğümünde
`Effects Enabled` tüm ışık efektlerini, `Animation Enabled` hareketi açıp kapatır.
Hareket kapatıldığında hafif sabit parıltı korunur.
`themes/pardex_logo_material.tres` içinden parlama süresi, ışık şiddeti ve renk
düzenlenebilir. Şeffaf logo dosyası değiştirilmez; ışıklar Compatibility
renderer ile canvas shader üzerinden çizilir.
