extends VBoxContainer

# Mağaza: welcome carousel, featured games, deals and new releases.
# Built from the real PARDEX catalog; PARDEX has no payment system yet, so
# games show their availability instead of prices and the deals shelf says
# that no campaign is running.

signal navigate(page: String)
signal play_requested(game_id: String)
signal toast(message: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")
const SLIDE_SECONDS := 8.0

var _slide := 0
var _hero_art: TextureRect
var _hero_tag: Label
var _hero_title: Label
var _hero_body: Label
var _hero_dots: HBoxContainer
var _hero_features: Control
var _featured: GridContainer
var _new_row: GridContainer
var _content_width := 1200.0


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	var body := UI.vbox(16)
	add_child(UI.scroll_page(body))

	body.add_child(_build_hero())

	var featured_header := UI.section_header("Öne Çıkanlar", "Tümünü Gör", 22)
	featured_header.add_child(UI.pill("Editörün Seçimi", UI.GOLD, "crown", 11))
	featured_header.move_child(featured_header.get_child(-1), 1)
	(featured_header.get_node("Link") as Button).pressed.connect(func(): navigate.emit("library"))
	body.add_child(featured_header)
	_featured = _grid()
	body.add_child(_featured)

	var deals_header := UI.section_header("İndirimler", "Tümünü Gör", 20, "percent", UI.RED)
	deals_header.add_child(UI.label("Kaçırılmayacak fırsatlar, sınırlı süreli indirimler.", 13, UI.TEXT_2))
	deals_header.move_child(deals_header.get_child(-1), 2)
	(deals_header.get_node("Link") as Button).visible = false
	body.add_child(deals_header)
	var deals := UI.panel(14)
	deals.custom_minimum_size.y = 76
	deals.add_child(UI.empty_state("percent", "Şu an aktif indirim yok", "Kampanyalar başladığında burada görünecek.", true))
	body.add_child(deals)

	var new_header := UI.section_header("Yeni Gelenler", "Tümünü Gör", 20, "sparkles", UI.ACCENT)
	new_header.add_child(UI.label("En yeni oyunlar şimdi PARDEX'te.", 13, UI.TEXT_2))
	new_header.move_child(new_header.get_child(-1), 2)
	(new_header.get_node("Link") as Button).pressed.connect(func(): navigate.emit("library"))
	body.add_child(new_header)
	_new_row = _grid()
	body.add_child(_new_row)

	_render_shelves()
	_show_slide(0)
	var timer := Timer.new()
	timer.wait_time = SLIDE_SECONDS
	timer.autostart = true
	timer.timeout.connect(func(): if is_visible_in_tree(): _show_slide(_slide + 1))
	add_child(timer)
	visibility_changed.connect(func(): if is_visible_in_tree(): _render_shelves())


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	return grid


func apply_layout(content_width: float) -> void:
	_content_width = content_width
	_featured.columns = 3 if content_width >= 1020.0 else 2
	_new_row.columns = 3 if content_width >= 1100.0 else 2
	if _hero_features != null:
		_hero_features.visible = content_width >= 900.0


# ------------------------------------------------------------------ hero

func _slides() -> Array:
	var result := [{
		"tag": "OYUNLARIN YENİ EVİ",
		"title": "PARDEX Mağazaya\nHoş Geldin",
		"body": "Yeni oyunları keşfet, arkadaşlarınla oyna\nve öne çıkan içerikleri hemen incele.",
		"banner": "res://assets/ui/home_hero_banner.png",
		"game": "",
	}]
	for entry in Catalog.GAMES:
		result.append({
			"tag": str(entry["badge"]).to_upper(),
			"title": str(entry["title"]),
			"body": str(entry["tagline"]),
			"banner": str(entry["banner"]),
			"game": str(entry["id"]),
		})
	return result


func _build_hero() -> Control:
	var frame := UI.image(null, Vector2(0, 330), 16)
	frame.add_theme_stylebox_override("panel", UI.glow_style(0, 16))
	_hero_art = frame.get_node("Art") as TextureRect
	frame.add_child(UI.shade(0.95, true))
	frame.add_child(UI.shade(0.55))

	var row := UI.hbox(20)
	frame.add_child(UI.margin(row, 36, 30, 26, 18))
	var text := UI.vbox(12)
	UI.expand(text)
	row.add_child(text)
	var tag_row := UI.hbox(8)
	tag_row.add_child(UI.icon("crown", 16, UI.ACCENT))
	_hero_tag = UI.label("", 13, UI.ACCENT, true)
	tag_row.add_child(_hero_tag)
	var tag_holder := UI.panel(0, UI.box(Color(UI.BG, 0.6), 8, UI.BORDER_HI, 1, 8))
	tag_holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag_holder.add_child(tag_row)
	text.add_child(tag_holder)
	_hero_title = UI.label("", 42, UI.TEXT, true)
	text.add_child(_hero_title)
	_hero_body = UI.label("", 16, UI.TEXT_2)
	text.add_child(_hero_body)
	var actions := UI.hbox(14)
	text.add_child(actions)
	var explore := UI.button("Şimdi İncele", "primary", 15, 50, "arrow_right")
	explore.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	explore.custom_minimum_size.x = 200
	explore.pressed.connect(_explore_slide)
	actions.add_child(explore)
	var wish := UI.button("İstek Listesi", "ghost", 15, 50, "heart")
	wish.custom_minimum_size.x = 180
	wish.pressed.connect(_toggle_slide_wishlist)
	actions.add_child(wish)
	text.add_child(UI.vspacer())

	var pager := UI.hbox(10)
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	var prev := UI.icon_button("chevron_left", "Önceki", 28)
	prev.pressed.connect(func(): _show_slide(_slide - 1))
	pager.add_child(prev)
	_hero_dots = UI.hbox(8)
	pager.add_child(_hero_dots)
	for index in _slides().size():
		var dot := Button.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.focus_mode = Control.FOCUS_NONE
		dot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		dot.pressed.connect(_show_slide.bind(index))
		_hero_dots.add_child(dot)
	var next := UI.icon_button("chevron_right", "Sonraki", 28)
	next.pressed.connect(func(): _show_slide(_slide + 1))
	pager.add_child(next)
	text.add_child(pager)

	var features := UI.vbox(22)
	features.alignment = BoxContainer.ALIGNMENT_CENTER
	features.custom_minimum_size.x = 190
	for feature in [
		["star", "PARDEX\nORİJİNALLERİ"],
		["check_circle", "GÜVENLİ\nOYUN OTURUMU"],
		["gamepad", "ONLINE\nODALAR"],
		["friends", "AKTİF\nTOPLULUK"],
	]:
		var line := UI.hbox(14)
		line.add_child(UI.icon(str(feature[0]), 30, UI.ACCENT))
		line.add_child(UI.label(str(feature[1]), 12, UI.TEXT_2, true))
		features.add_child(line)
	_hero_features = features
	row.add_child(features)
	return frame


func _show_slide(index: int) -> void:
	var slides := _slides()
	_slide = posmod(index, slides.size())
	var slide: Dictionary = slides[_slide]
	_hero_art.texture = Catalog.texture(str(slide["banner"]))
	_hero_tag.text = str(slide["tag"])
	_hero_title.text = str(slide["title"])
	_hero_body.text = str(slide["body"])
	for dot_index in _hero_dots.get_child_count():
		var dot := _hero_dots.get_child(dot_index) as Button
		var style := UI.box(UI.ACCENT if dot_index == _slide else Color(1, 1, 1, 0.3), 5)
		for state in ["normal", "hover", "pressed"]:
			dot.add_theme_stylebox_override(state, style)


func _explore_slide() -> void:
	var game_id := str(_slides()[_slide]["game"])
	if game_id.is_empty():
		navigate.emit("library")
	else:
		_open_game(game_id)


func _toggle_slide_wishlist() -> void:
	var game_id := str(_slides()[_slide]["game"])
	if game_id.is_empty():
		game_id = str(Catalog.GAMES[0]["id"])
	var added := Catalog.toggle_wishlist(game_id)
	toast.emit("%s istek listene %s." % [str(Catalog.game(game_id)["title"]), "eklendi" if added else "çıkarıldı"])
	_render_shelves()


# ------------------------------------------------------------------ shelves

func _render_shelves() -> void:
	UI.clear(_featured)
	for entry in Catalog.GAMES:
		_featured.add_child(_featured_card(entry))
	UI.clear(_new_row)
	for entry in Catalog.GAMES:
		_new_row.add_child(_new_card(entry))


func _heart(game_id: String, size := 34.0) -> Button:
	var wished := Catalog.is_wishlisted(game_id)
	var heart := UI.icon_button("heart_fill" if wished else "heart", "İstek listesi", size, UI.RED if wished else UI.TEXT, true)
	heart.add_theme_stylebox_override("normal", UI.box(Color(UI.BG, 0.65), 9, Color(1, 1, 1, 0.18), 1))
	heart.pressed.connect(func():
		var added := Catalog.toggle_wishlist(game_id)
		toast.emit("%s istek listene %s." % [str(Catalog.game(game_id)["title"]), "eklendi" if added else "çıkarıldı"])
		_render_shelves()
	)
	return heart


func _availability(entry: Dictionary) -> Control:
	var state: Array = Catalog.status(str(entry["id"]))
	var color: Color = {"green": UI.GREEN, "amber": UI.AMBER, "muted": UI.TEXT_3}[state[2]]
	var row := UI.hbox(10)
	row.add_child(UI.pill(str(state[0]), color, str(state[1]), 12, state[2] == "green"))
	row.add_child(UI.label("Oynanabilir" if bool(entry["playable"]) else "Çok yakında", 14, UI.TEXT, true))
	return row


func _badge_color(badge: String) -> Color:
	match badge:
		"Popüler": return UI.RED
		"Editörün Seçimi": return UI.GOLD
		_: return UI.ACCENT


func _badge_icon(badge: String) -> String:
	match badge:
		"Popüler": return "fire"
		"Editörün Seçimi": return "crown"
		_: return "sparkles"


func _featured_card(entry: Dictionary) -> Control:
	var game_id := str(entry["id"])
	var frame := UI.image(Catalog.texture(str(entry["cover"])), Vector2(0, 190), 12)
	UI.expand(frame)
	frame.add_theme_stylebox_override("panel", UI.card_style(0))
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame.gui_input.connect(_on_card_input.bind(game_id))
	frame.add_child(UI.shade(0.95))
	var column := UI.vbox(2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(UI.margin(column, 12, 12, 12, 12))
	var badge := str(entry["badge"])
	column.add_child(UI.pill(badge, _badge_color(badge), _badge_icon(badge), 12))
	column.add_child(UI.vspacer())
	var bottom := UI.hbox(10)
	column.add_child(bottom)
	var info := UI.vbox(3)
	UI.expand(info)
	info.add_child(UI.fit(UI.label(str(entry["title"]), 18, UI.TEXT, true)))
	info.add_child(UI.fit(UI.label("   ".join(entry["genres"]), 13, UI.TEXT_2)))
	info.add_child(_availability(entry))
	bottom.add_child(info)
	var heart := _heart(game_id, 38)
	heart.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(heart)
	return frame


func _new_card(entry: Dictionary) -> Control:
	var game_id := str(entry["id"])
	var card := UI.panel(0, UI.card_style(0))
	UI.expand(card)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_card_input.bind(game_id))
	var row := UI.hbox(12)
	card.add_child(row)
	var art := UI.image(Catalog.texture(str(entry["cover"])), Vector2(130, 80), 12)
	var art_column := UI.vbox(0)
	art_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_row := UI.hbox(0)
	badge_row.add_child(UI.spacer())
	badge_row.add_child(UI.pill("Yeni", UI.ACCENT, "", 11, true))
	art_column.add_child(badge_row)
	art.add_child(UI.margin(art_column, 6, 6, 6, 6))
	row.add_child(art)
	var text := UI.vbox(3)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.expand(text)
	text.add_child(UI.fit(UI.label(str(entry["title"]), 14, UI.TEXT, true)))
	text.add_child(UI.fit(UI.label("  ".join(entry["genres"]), 12, UI.TEXT_3)))
	text.add_child(UI.label("Oynanabilir" if bool(entry["playable"]) else "Çok yakında", 14, UI.TEXT, true))
	row.add_child(text)
	var heart := _heart(game_id, 32)
	heart.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(UI.margin(heart, 0, 8, 10, 8))
	return card


func _on_card_input(event: InputEvent, game_id: String) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		_open_game(game_id)


func _open_game(game_id: String) -> void:
	var entry := Catalog.game(game_id)
	if bool(entry.get("playable", false)):
		play_requested.emit(game_id)
	else:
		toast.emit("%s çok yakında PARDEX'te. İstek listene ekleyebilirsin." % str(entry.get("title", "Bu oyun")))
