extends VBoxContainer

# Ana Sayfa: featured game carousel, today's agenda, recently played and
# quick start. Built from the real catalog and local play history.

signal navigate(page: String)
signal play_requested(game_id: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")
const FEATURE_SECONDS := 7.0

var top_row: BoxContainer
var bottom_row: BoxContainer
var _feature_index := 0
var _feature_art: TextureRect
var _feature_title: Label
var _feature_tagline: Label
var _feature_play: Button
var _feature_dots: HBoxContainer
var _agenda_list: VBoxContainer
var _recent_grid: GridContainer
var _quick_list: VBoxContainer
var _side_panels: Array[Control] = []


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body := UI.vbox(14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	top_row = BoxContainer.new()
	top_row.add_theme_constant_override("separation", 14)
	body.add_child(top_row)
	top_row.add_child(_build_feature())
	top_row.add_child(_build_agenda())

	bottom_row = BoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 14)
	body.add_child(bottom_row)
	bottom_row.add_child(_build_recent())
	bottom_row.add_child(_build_quick_start())

	_show_feature(0)
	var timer := Timer.new()
	timer.wait_time = FEATURE_SECONDS
	timer.autostart = true
	timer.timeout.connect(func(): if is_visible_in_tree(): _show_feature(_feature_index + 1))
	add_child(timer)

	PardexOnline.connection_state_changed.connect(func(_state): _render_agenda())
	PardexOnline.social_state_changed.connect(func(_state): _render_agenda())
	PardexOnline.room_state_changed.connect(func(_room): _render_agenda())
	PardexOnline.room_left.connect(_render_agenda)
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh())
	refresh()


func refresh() -> void:
	_render_agenda()
	_render_recent()
	_render_quick_start()


func apply_layout(content_width: float) -> void:
	top_row.vertical = content_width < 760.0
	bottom_row.vertical = content_width < 900.0
	var side_width := clampf(content_width * 0.3, 250.0, 380.0)
	for side in _side_panels:
		var stacked := (side.get_parent() as BoxContainer).vertical
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL if stacked else Control.SIZE_FILL
		side.custom_minimum_size.x = 0.0 if stacked else side_width
	var recent_width := content_width if bottom_row.vertical else content_width - side_width - 14.0
	_recent_grid.columns = clampi(floori((recent_width + 10.0) / 150.0), 2, 4)


func _build_feature() -> Control:
	var frame := UI.image(null, Vector2(0, 300), 14)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feature_art = frame.get_child(0) as TextureRect
	frame.add_child(UI.shade(0.92, true))
	frame.add_child(UI.shade(0.75))

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 14)
	frame.add_child(margin)

	var column := UI.vbox(8)
	margin.add_child(column)
	column.add_child(_vspace())
	column.add_child(UI.tag("ÖNE ÇIKAN", UI.ACCENT))
	_feature_title = UI.label("", 30, UI.TEXT, true)
	column.add_child(_feature_title)
	_feature_tagline = UI.label("", 13, UI.TEXT_2)
	column.add_child(_feature_tagline)

	var actions := UI.hbox(10)
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	_feature_play = UI.button("Hemen Oyna", "primary", 13, 38)
	_feature_play.custom_minimum_size.x = 120
	_feature_play.pressed.connect(func(): play_requested.emit(str(Catalog.GAMES[_feature_index]["id"])))
	actions.add_child(_feature_play)
	var details := UI.button("Detaylar", "ghost", 13, 38)
	details.custom_minimum_size.x = 100
	details.pressed.connect(func(): navigate.emit("library"))
	actions.add_child(details)

	_feature_dots = UI.hbox(6)
	_feature_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_feature_dots)
	for index in Catalog.GAMES.size():
		var dot := Button.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.focus_mode = Control.FOCUS_NONE
		dot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		dot.pressed.connect(_show_feature.bind(index))
		_feature_dots.add_child(dot)
	return frame


func _vspace() -> Control:
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return space


func _show_feature(index: int) -> void:
	_feature_index = posmod(index, Catalog.GAMES.size())
	var entry: Dictionary = Catalog.GAMES[_feature_index]
	_feature_art.texture = Catalog.texture(str(entry["banner"]))
	_feature_title.text = str(entry["title"])
	_feature_tagline.text = str(entry["tagline"])
	var playable := bool(entry["playable"])
	_feature_play.text = "Hemen Oyna" if playable else "Yakında"
	_feature_play.disabled = not playable
	for dot_index in _feature_dots.get_child_count():
		var dot := _feature_dots.get_child(dot_index) as Button
		var active := dot_index == _feature_index
		dot.custom_minimum_size.x = 18.0 if active else 8.0
		var style := UI.box(UI.ACCENT if active else Color(1, 1, 1, 0.3), 4)
		for state in ["normal", "hover", "pressed"]:
			dot.add_theme_stylebox_override(state, style)


func _build_agenda() -> Control:
	var card := UI.panel(14)
	_side_panels.append(card)
	var column := UI.vbox(10)
	card.add_child(column)
	column.add_child(UI.section_header("Bugünün Gündemi", "", 14))
	_agenda_list = UI.vbox(10)
	_agenda_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_agenda_list)
	var footer := UI.hbox()
	footer.add_child(UI.spacer())
	var link := UI.button("Tüm Haberler  →", "link", 12, 24)
	link.pressed.connect(func(): navigate.emit("discover"))
	footer.add_child(link)
	column.add_child(footer)
	return card


func _render_agenda() -> void:
	if _agenda_list == null:
		return
	UI.clear(_agenda_list)
	var friends: Array = PardexOnline.social_state.get("friends", []) if typeof(PardexOnline.social_state.get("friends", [])) == TYPE_ARRAY else []
	var online_count := 0
	for friend in friends:
		if typeof(friend) == TYPE_DICTIONARY and str(friend.get("presence", "offline")) != "offline":
			online_count += 1
	var online := PardexOnline.is_online()
	_agenda_list.add_child(_agenda_row(
		"res://assets/ui/home_agenda_announcement.png",
		"PARDEX Online " + ("aktif" if online else "bağlantısı bekleniyor"),
		"Odalar, arkadaşlar ve davetler çevrimiçi." if online else "Bağlantı kurulunca sosyal özellikler açılır.",
		"Şimdi"
	))
	_agenda_list.add_child(_agenda_row(
		"res://assets/ui/home_agenda_social.png",
		"%d arkadaşın çevrimiçi" % online_count if not friends.is_empty() else "Arkadaşlarını ekle",
		"Toplam %d arkadaş" % friends.size() if not friends.is_empty() else "Arkadaşlar sayfasından PARDEX kullanıcılarını bul.",
		"Canlı"
	))
	var room := PardexOnline.current_room
	_agenda_list.add_child(_agenda_row(
		"res://assets/ui/home_agenda_games.png",
		"Korsanların Hazinesi odası: %s" % str(room.get("code", "")) if not room.is_empty() else "Korsanların Hazinesi hazır",
		"%d oyuncu odada" % (room.get("members", []) as Array).size() if not room.is_empty() else "Oda kur, arkadaşlarını davet et, birlikte oyna.",
		"Oyun"
	))


func _agenda_row(icon_path: String, title: String, body: String, when: String) -> Control:
	var row := UI.hbox(10)
	row.add_child(UI.image(Catalog.texture(icon_path), Vector2(44, 44), 8))
	var text := UI.vbox(1)
	UI.expand(text)
	text.add_child(UI.fit(UI.label(title, 13, UI.TEXT, true)))
	text.add_child(UI.fit(UI.label(body, 11, UI.TEXT_2)))
	text.add_child(UI.label(when, 10, UI.TEXT_3))
	row.add_child(text)
	return row


func _build_recent() -> Control:
	var column := UI.vbox(10)
	UI.expand(column, 2.0)
	var header := UI.section_header("Son Oynananlar", "Kütüphane  →", 15)
	(header.get_node("Link") as Button).pressed.connect(func(): navigate.emit("library"))
	column.add_child(header)
	_recent_grid = GridContainer.new()
	_recent_grid.columns = 4
	_recent_grid.add_theme_constant_override("h_separation", 10)
	_recent_grid.add_theme_constant_override("v_separation", 10)
	column.add_child(_recent_grid)
	return column


func _render_recent() -> void:
	UI.clear(_recent_grid)
	var recent := Catalog.recent_games()
	# Fill the row with the rest of the catalog so the shelf is never empty;
	# games never launched here say so instead of inventing a play date.
	for entry in Catalog.GAMES:
		if recent.size() >= 4:
			break
		if recent.any(func(item): return item["id"] == entry["id"]):
			continue
		var item: Dictionary = entry.duplicate()
		item["last_played"] = 0
		recent.append(item)
	for entry in recent:
		_recent_grid.add_child(_poster(entry))


func _poster(entry: Dictionary) -> Control:
	var card := UI.panel(0, UI.box(UI.SURFACE, 10, UI.BORDER, 1))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var column := UI.vbox(0)
	card.add_child(column)
	var art := UI.image(Catalog.texture(str(entry["cover"])), Vector2(0, 150), 10)
	column.add_child(art)
	var play := UI.button("▶", "primary", 12, 30)
	play.custom_minimum_size.x = 30
	play.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	play.offset_left = -38
	play.offset_top = -38
	play.offset_right = -8
	play.offset_bottom = -8
	play.disabled = not bool(entry["playable"])
	play.tooltip_text = "Oyna" if bool(entry["playable"]) else "Yakında"
	play.pressed.connect(func(): play_requested.emit(str(entry["id"])))
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(overlay)
	overlay.add_child(play)
	var info := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		info.add_theme_constant_override("margin_" + side, 8)
	column.add_child(info)
	var text := UI.vbox(1)
	info.add_child(text)
	text.add_child(UI.fit(UI.label(str(entry["title"]), 13, UI.TEXT, true)))
	text.add_child(UI.fit(UI.label(Catalog.last_played_text(int(entry.get("last_played", 0))), 10, UI.TEXT_3)))
	return card


func _build_quick_start() -> Control:
	var card := UI.panel(14)
	_side_panels.append(card)
	var column := UI.vbox(10)
	card.add_child(column)
	column.add_child(UI.section_header("Hızlı Başlat", "", 15))
	_quick_list = UI.vbox(8)
	column.add_child(_quick_list)
	return card


func _render_quick_start() -> void:
	UI.clear(_quick_list)
	for entry in Catalog.GAMES:
		var row := UI.panel(0, UI.box(UI.SURFACE_2, 8, UI.BORDER, 1, 6))
		var line := UI.hbox(10)
		row.add_child(line)
		line.add_child(UI.image(Catalog.texture(str(entry["cover"])), Vector2(34, 34), 6))
		var name_label := UI.fit(UI.label(str(entry["title"]), 12, UI.TEXT))
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(UI.expand(name_label))
		var playable := bool(entry["playable"])
		var play := UI.button("Oyna" if playable else "Yakında", "primary", 11, 28)
		play.custom_minimum_size.x = 62
		play.disabled = not playable
		play.pressed.connect(func(): play_requested.emit(str(entry["id"])))
		line.add_child(play)
		_quick_list.add_child(row)
