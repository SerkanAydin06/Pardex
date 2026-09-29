extends RefCounted

# The PARDEX game catalog and the local play history.
# The catalog lists the games PARDEX actually ships; the history is recorded on
# this computer when a game is launched, so "Son Oynananlar" and the profile
# statistics only ever show real activity.

const ACTIVITY_PATH := "user://pardex_activity.cfg"

const GAMES := [
	{
		"id": "korsanlar",
		"title": "Korsanların Hazinesi",
		"genre": "Strateji",
		"tags": ["Strateji", "Çok Oyunculu", "Bağımsız"],
		"players": "1–4 oyuncu",
		"tagline": "Mürettebatını topla, hazineyi ilk sen bul.",
		"cover": "res://assets/ui/placeholder_korsan.png",
		"banner": "res://assets/ui/home_hero_banner.png",
		"playable": true,
	},
	{
		"id": "vex",
		"title": "VEX",
		"genre": "Aksiyon",
		"tags": ["Aksiyon", "Bağımsız"],
		"players": "Tek oyunculu",
		"tagline": "İnsanlığın son umutlarından biri ol.",
		"cover": "res://assets/ui/placeholder_vex.png",
		"banner": "res://assets/ui/top_banner.png",
		"playable": false,
	},
	{
		"id": "firtina",
		"title": "Fırtına Vadisi",
		"genre": "Macera",
		"tags": ["Macera", "RYO", "Bağımsız"],
		"players": "Tek oyunculu",
		"tagline": "Unutulmuş topraklarda kendi hikâyeni yaz.",
		"cover": "res://assets/ui/placeholder_firtina.png",
		"banner": "res://assets/ui/left_banner.png",
		"playable": false,
	},
]

const CATEGORIES := ["Tümü", "Aksiyon", "Macera", "RYO", "Strateji", "Simülasyon", "Spor", "Korku", "Bağımsız", "Çok Oyunculu"]


static func game(game_id: String) -> Dictionary:
	for entry in GAMES:
		if entry["id"] == game_id:
			return entry
	return {}


static func texture(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func record_launch(game_id: String) -> void:
	var config := ConfigFile.new()
	config.load(ACTIVITY_PATH)
	config.set_value(game_id, "last_played", int(Time.get_unix_time_from_system()))
	config.set_value(game_id, "launches", int(config.get_value(game_id, "launches", 0)) + 1)
	config.save(ACTIVITY_PATH)


# Games launched on this computer, most recent first:
# [{game..., "last_played": unix, "launches": n}]
static func recent_games() -> Array:
	var config := ConfigFile.new()
	if config.load(ACTIVITY_PATH) != OK:
		return []
	var result := []
	for entry in GAMES:
		var game_id := str(entry["id"])
		if not config.has_section(game_id):
			continue
		var item: Dictionary = entry.duplicate()
		item["last_played"] = int(config.get_value(game_id, "last_played", 0))
		item["launches"] = int(config.get_value(game_id, "launches", 0))
		result.append(item)
	result.sort_custom(func(a, b): return a["last_played"] > b["last_played"])
	return result


static func last_played_text(unix_time: int) -> String:
	if unix_time <= 0:
		return "Henüz oynanmadı"
	var days := int((Time.get_unix_time_from_system() - unix_time) / 86400.0)
	if days <= 0:
		return "Son oynama: Bugün"
	if days == 1:
		return "Son oynama: Dün"
	return "Son oynama: %d gün önce" % days
