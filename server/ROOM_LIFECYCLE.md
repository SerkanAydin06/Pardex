# PARDEX Room Lifecycle

PARDEX odaları tek bir `launching` boolean'ı yerine açık bir yaşam döngüsü kullanır.

## Durumlar

| State | Anlamı |
| --- | --- |
| `lobby` | Oyuncular odada, hazır olabilir ve yeni oyuncu/davet kabul edilir. |
| `launching` | Host oyunu başlattı; istemciler oyun sürecini açıp aynı `match_id` ile bağlanıyor. |
| `in_game` | Odadaki tüm mevcut oyuncular `game_connected` bildirdi. |
| `ended` | Aktif maç sona erdi; sonuç bilgisi yayınlandı, oda hâlâ tutuluyor. |
| `closed` | Son üye de odadan çıktı. Oda bellekten silinir. |

Geçişler:

```text
lobby -> launching -> in_game -> ended -> lobby
          |                         
          +---- launch_failed ----> lobby

last member leaves -> closed
```

## Oda payload'ı

Yeni alanlar:

- `state`
- `match_id`
- `launch_started_at`
- `started_at`
- `ended_at`
- `in_game`
- `ended`
- her üye için `game_state`
- her üye için `game_connected_at`
- her üye için `connection_state` (`online`, `reconnecting`, `offline`)

`launching` alanı eski istemciler için geriye uyumluluk amacıyla tutulur ve `state == "launching"` değerinden türetilir.

## Başlatma

Host `start_game` gönderir. Sunucu:

1. Odanın `lobby` durumunda olduğunu doğrular.
2. En az iki oyuncu ve herkesin hazır olduğunu doğrular.
3. Oyun sunucusu atamasını doğrular.
4. Kriptografik rastgele bir `match_id` üretir.
5. Odayı `launching` durumuna geçirir.
6. Tüm üyelere `game_start` yollar.

`game_start` payload'ındaki `match_id`, odanın mevcut `room.match_id` değeriyle aynıdır.

## Oyuna bağlanma onayı

Launcher veya oyun istemcisi, oyun sunucusuna gerçekten bağlandıktan sonra PARDEX Online'a şunu gönderir:

```json
{
  "type": "game_connected",
  "match_id": "..."
}
```

Sunucu yalnız mevcut `match_id` ile eşleşen bildirimi kabul eder. Her oyuncunun `game_state` alanı ayrı ayrı `in_game` olur. Tüm mevcut üyeler bağlandığında oda `in_game` durumuna geçer ve `game_started` yayınlanır.

Bu yüzden process'in yalnızca açılmış olması artık oyuncunun gerçekten oyunda olduğu anlamına gelmez.

## Launch başarısızlığı

Oyuna bağlanmadan önce istemci:

```json
{
  "type": "launch_failed",
  "match_id": "...",
  "reason": "..."
}
```

gönderebilir. Bu mesaj yalnız `launching` aşamasında rollback yapar. Oda `lobby` durumuna döner, `match_id` temizlenir ve tüm hazır durumları sıfırlanır.

Oda `in_game` olduktan sonra tek bir istemcinin launch hatası tüm maçı geriye düşürmez.

## Oyun sonu

Şimdilik host aşağıdaki mesajla aktif maçı sonlandırabilir:

```json
{
  "type": "game_ended",
  "match_id": "...",
  "result": {}
}
```

Sunucu odayı `ended` yapar ve `game_ended` yayınlar. Host daha sonra:

```json
{
  "type": "return_to_lobby"
}
```

göndererek aynı grubu yeni maç için `lobby` durumuna döndürebilir.

## Güven sınırı

Host-authoritative `game_ended` geçici geliştirme katmanıdır. Korsanların Hazinesi gerçek oyun entegrasyonunda maç başlangıcı/bitişi ve sonuçları, launcher istemcisinden değil güvenilir oyun sunucusundan doğrulanacaktır. `match_id` bu entegrasyonun ortak oturum kimliğidir.

## Reconnect davranışı

PARDEX launcher WebSocket'i koptuğunda mevcut 30 saniyelik session recovery çalışmaya devam eder. Bu sürede üyenin oda payload'ındaki `connection_state` değeri `reconnecting` olur. Aynı resume token ile dönerse kullanıcı, oda ve maç kimliği korunur. Süre dolarsa üye odadan çıkarılır.

`launching` aşamasında bir üyenin tamamen ayrılması launch'ı iptal eder. `in_game` aşamasında bir launcher bağlantısının düşmesi ise maçı otomatik olarak `lobby` durumuna çekmez.
