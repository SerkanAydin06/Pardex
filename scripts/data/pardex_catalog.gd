extends RefCounted

# The PARDEX game catalog plus everything PARDEX remembers locally about how
# this computer uses it: favorites, wish list, play sessions, playtime and an
# activity log. Nothing here is invented: every number shown in the store,
# library and profile comes from the catalog or from these records.

const ACTIVITY_PATH := "user://pardex_activity.cfg"
const MAX_EVENTS := 40

const GAMES := [
	{
		"id": "korsanlar",
		"title": "Korsanların Hazinesi",
		"genres": ["Strateji", "Çok Oyunculu"],
		"players": "1–4 oyuncu",
		"tagline": "Mürettebatını topla, hazineyi ilk sen bul.",
		"cover": "res://assets/ui/placeholder_korsan.png",
		"banner": "res://assets/ui/home_hero_banner.png",
		"badge": "Editörün Seçimi",
		"playable": true,
	},
	{
		"id": "vex",
		"title": "VEX",
		"genres": ["Aksiyon", "Bilim Kurgu"],
		"players": "Tek oyunculu",
		"tagline": "Karanlık bir gelecekte insanlığın son umutlarından biri ol.",
		"cover": "res://assets/ui/placeholder_vex.png",
		"banner": "res://assets/ui/top_banner.png",
		"badge": "Yeni",
		"playable": false,
	},
	{
		"id": "firtina",
		"title": "Fırtına Vadisi",
		"genres": ["Macera", "RPG"],
		"players": "Tek oyunculu",
		"tagline": "Unutulmuş topraklarda kendi hikâyeni yaz.",
		"cover": "res://assets/ui/placeholder_firtina.png",
		"banner": "res://assets/ui/left_banner.png",
		"badge": "Yeni",
		"playable": false,
	},
]


static func game(game_id: String) -> Dictionary:
	for entry in GAMES:
		if entry["id"] == game_id:
			return entry
	return {}


static func texture(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(ACTIVITY_PATH)
	return config


# ------------------------------------------------------------------ install

# Korsanların Hazinesi ships as a packaged executable next to PARDEX (exported
# builds) or as the sibling Godot project (editor); other games are not
# released yet.
static func is_installed(game_id: String) -> bool:
	if game_id != "korsanlar":
		return false
	if OS.has_feature("editor"):
		var parent_dir := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
		var directory := DirAccess.open(parent_dir)
		if directory == null:
			return false
		for entry in directory.get_directories():
			if "korsan" in entry.to_lower() and FileAccess.file_exists(parent_dir.path_join(entry).path_join("project.godot")):
				return true
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var launcher := tree.root.get_node_or_null("PardexGameLauncher")
	return launcher != null and not str(launcher.call("_find_korsan_executable")).is_empty()


static func status(game_id: String) -> Array:
	var entry := game(game_id)
	if entry.is_empty() or not bool(entry["playable"]):
		return ["Yakında", "clock", "muted"]
	if is_installed(game_id):
		return ["Yüklü", "check", "green"]
	return ["Kurulum Gerekli", "download", "amber"]


# ------------------------------------------------------------------ lists

static func _flag_list(key: String) -> Array:
	var value = _load().get_value("pardex", key, [])
	return value if typeof(value) == TYPE_ARRAY else []


static func _toggle(key: String, game_id: String) -> bool:
	var config := _load()
	var items: Array = config.get_value("pardex", key, [])
	var added := not items.has(game_id)
	if added:
		items.append(game_id)
	else:
		items.erase(game_id)
	config.set_value("pardex", key, items)
	config.save(ACTIVITY_PATH)
	return added


static func favorites() -> Array:
	return _flag_list("favorites")


static func is_favorite(game_id: String) -> bool:
	return favorites().has(game_id)


static func toggle_favorite(game_id: String) -> bool:
	return _toggle("favorites", game_id)


static func is_wishlisted(game_id: String) -> bool:
	return _flag_list("wishlist").has(game_id)


static func toggle_wishlist(game_id: String) -> bool:
	return _toggle("wishlist", game_id)


# ------------------------------------------------------------------ activity

# First day PARDEX ran on this computer (shown as "PARDEX'e katıldı").
static func joined_at() -> int:
	var config := _load()
	var joined := int(config.get_value("pardex", "joined_at", 0))
	if joined <= 0:
		joined = int(Time.get_unix_time_from_system())
		config.set_value("pardex", "joined_at", joined)
		config.save(ACTIVITY_PATH)
	return joined


static func record_launch(game_id: String) -> void:
	var config := _load()
	var now := int(Time.get_unix_time_from_system())
	config.set_value(game_id, "last_played", now)
	config.set_value(game_id, "launches", int(config.get_value(game_id, "launches", 0)) + 1)
	config.save(ACTIVITY_PATH)
	add_event("play", "%s oynadı" % str(game(game_id).get("title", game_id)), game_id)


static func add_playtime(game_id: String, seconds: int) -> void:
	if seconds <= 0:
		return
	var config := _load()
	config.set_value(game_id, "playtime", int(config.get_value(game_id, "playtime", 0)) + seconds)
	config.save(ACTIVITY_PATH)


static func add_event(kind: String, text: String, game_id := "") -> void:
	var config := _load()
	var events: Array = config.get_value("pardex", "events", [])
	events.push_front({"kind": kind, "text": text, "game": game_id, "at": int(Time.get_unix_time_from_system())})
	config.set_value("pardex", "events", events.slice(0, MAX_EVENTS))
	config.save(ACTIVITY_PATH)


static func events() -> Array:
	return _flag_list("events")


# Catalog entries with local stats: last_played, launches, playtime (seconds).
static func games_with_stats() -> Array:
	var config := _load()
	var result := []
	for entry in GAMES:
		var item: Dictionary = entry.duplicate()
		var game_id := str(entry["id"])
		item["last_played"] = int(config.get_value(game_id, "last_played", 0))
		item["launches"] = int(config.get_value(game_id, "launches", 0))
		item["playtime"] = int(config.get_value(game_id, "playtime", 0))
		item["favorite"] = favorites().has(game_id)
		item["installed"] = is_installed(game_id)
		result.append(item)
	return result


# Games launched on this computer, most recent first.
static func recent_games() -> Array:
	var played := games_with_stats().filter(func(item): return item["last_played"] > 0)
	played.sort_custom(func(a, b): return a["last_played"] > b["last_played"])
	return played


static func total_playtime() -> int:
	var total := 0
	for item in games_with_stats():
		total += int(item["playtime"])
	return total


# ------------------------------------------------------------------ text

static func ago(unix_time: int) -> String:
	if unix_time <= 0:
		return "Henüz oynanmadı"
	var seconds := int(Time.get_unix_time_from_system()) - unix_time
	if seconds < 60:
		return "Az önce"
	if seconds < 3600:
		return "%d dk önce" % (seconds / 60)
	if seconds < 86400:
		return "%d saat önce" % (seconds / 3600)
	if seconds < 86400 * 7:
		return "%d gün önce" % (seconds / 86400)
	return "%d hafta önce" % (seconds / (86400 * 7))


static func hours(seconds: int) -> String:
	if seconds <= 0:
		return "0 saat"
	if seconds < 3600:
		return "%d dk" % maxi(1, seconds / 60)
	return "%d saat" % (seconds / 3600)


static func date_text(unix_time: int) -> String:
	const MONTHS := ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
	var date := Time.get_date_dict_from_unix_time(unix_time)
	return "%d %s %d" % [date["day"], MONTHS[int(date["month"]) - 1], date["year"]]
