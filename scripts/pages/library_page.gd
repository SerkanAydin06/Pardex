extends VBoxContainer

# Kütüphane: hero with library stats, quick start, filter tabs, search, sort,
# grid/list views, recently played and "Devam Et". Install state, favorites,
# last played and playtime are real (catalog + local records).

signal play_requested(game_id: String)
signal toast(message: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")
const FILTERS := [["all", "Tümü", ""], ["installed", "Yüklü", "download"], ["recent", "Son Oynanan", "clock"], ["favorites", "Favoriler", "heart"]]
const SORTS := ["En Son Eklenen", "A → Z", "Son Oynanan"]
const HERO_HEIGHT := 300.0

var _filter := "all"
var _query := ""
var _sort := 0
var _list_view := false
var _stats_row: HBoxContainer
var _quick_list: VBoxContainer
var _filter_buttons: Dictionary = {}
var _grid: GridContainer
var _recent_row: HBoxContainer
var _continue_list: VBoxContainer
var _top: BoxContainer
var _bottom: BoxContainer
var _toolbar: BoxContainer
var _grid_button: Button
var _list_button: Button
var _game_menu: PopupMenu
var _menu_game := ""
var _content_width := 1200.0


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	var body := UI.vbox(16)
	add_child(UI.scroll_page(body))

	_top = BoxContainer.new()
	_top.add_theme_constant_override("separation", 16)
	body.add_child(_top)
	_top.add_child(_build_hero())
	_top.add_child(_build_quick_start())

	body.add_child(_build_toolbar())
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	body.add_child(_grid)

	_bottom = BoxContainer.new()
	_bottom.add_theme_constant_override("separation", 16)
	body.add_child(_bottom)
	_bottom.add_child(_build_recent())
	_bottom.add_child(_build_continue())

	_game_menu = PopupMenu.new()
	add_child(_game_menu)
	_game_menu.id_pressed.connect(_on_menu)
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh())
	refresh()


func set_query(query: String) -> void:
	_query = query.strip_edges().to_lower()
	if is_node_ready():
		_render_grid()


func refresh() -> void:
	_render_stats()
	_render_quick_start()
	_render_filters()
	_render_grid()
	_render_recent()
	_render_continue()


func apply_layout(content_width: float) -> void:
	_content_width = content_width
	_top.vertical = content_width < 900.0
	_bottom.vertical = content_width < 900.0
	for side in [_top.get_child(1), _bottom.get_child(1)]:
		var control := side as Control
		control.custom_minimum_size.x = 0.0 if _top.vertical else clampf(content_width * 0.32, 320.0, 460.0)
	_grid.columns = 1 if _list_view else clampi(floori((content_width + 14.0) / 210.0), 2, 6)
	if _toolbar != null:
		_toolbar.vertical = content_width < 1040.0


# ------------------------------------------------------------------ data

func _games() -> Array:
	var games := Catalog.games_with_stats()
	match _filter:
		"installed": games = games.filter(func(g): return g["installed"])
		"recent": games = games.filter(func(g): return g["last_played"] > 0)
		"favorites": games = games.filter(func(g): return g["favorite"])
	if not _query.is_empty():
		games = games.filter(func(g): return _query in str(g["title"]).to_lower() or _query in " ".join(g["genres"]).to_lower())
	match _sort:
		1: games.sort_custom(func(a, b): return str(a["title"]) < str(b["title"]))
		2: games.sort_custom(func(a, b): return a["last_played"] > b["last_played"])
	return games


func _count(kind: String) -> int:
	var games := Catalog.games_with_stats()
	match kind:
		"installed": return games.filter(func(g): return g["installed"]).size()
		"recent": return games.filter(func(g): return g["last_played"] > 0).size()
		"favorites": return games.filter(func(g): return g["favorite"]).size()
	return games.size()


# ------------------------------------------------------------------ hero

func _build_hero() -> Control:
	var frame := UI.image(Catalog.texture("res://assets/ui/home_hero_banner.png"), Vector2(0, HERO_HEIGHT), 16)
	UI.expand(frame, 2.0)
	frame.add_theme_stylebox_override("panel", UI.glow_style(0, 16))
	frame.add_child(UI.shade(0.95, true))
	var column := UI.vbox(10)
	frame.add_child(UI.margin(column, 30, 20, 24, 20))
	var tag := UI.panel(0, UI.box(Color(UI.BG, 0.6), 8, UI.BORDER_HI, 1, 8))
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var tag_row := UI.hbox(8)
	tag_row.add_child(UI.icon("crown", 15, UI.ACCENT))
	tag_row.add_child(UI.label("OYUN KÜTÜPHANEN", 12, UI.ACCENT, true))
	tag.add_child(tag_row)
	column.add_child(tag)
	column.add_child(UI.label("Oyun Kütüphanen", 42, UI.TEXT, true))
	column.add_child(UI.label("Tüm oyunların, her zaman seninle.\nKeşfet, oyna ve macerana kaldığın yerden devam et.", 15, UI.TEXT_2))
	column.add_child(UI.vspacer())
	_stats_row = UI.hbox(10)
	column.add_child(_stats_row)
	return frame


func _render_stats() -> void:
	UI.clear(_stats_row)
	for stat in [
		["gamepad", str(_count("all")), "Sahip Olunan", UI.ACCENT],
		["download", str(_count("installed")), "Yüklü", UI.ACCENT],
		["clock", str(_count("recent")), "Son Oynanan", UI.ACCENT],
		["heart", str(_count("favorites")), "Favoriler", UI.RED],
	]:
		var tile := UI.stat_tile(str(stat[0]), str(stat[1]), str(stat[2]), stat[3])
		tile.add_theme_stylebox_override("panel", UI.box(Color(UI.BG, 0.72), 12, UI.BORDER_HI, 1, 10))
		_stats_row.add_child(UI.expand(tile))


func _build_quick_start() -> Control:
	var card := UI.panel(16)
	var column := UI.vbox(10)
	card.add_child(column)
	column.add_child(UI.section_header("Hızlı Başlat", "", 20))
	_quick_list = UI.vbox(8)
	column.add_child(_quick_list)
	return card


func _render_quick_start() -> void:
	UI.clear(_quick_list)
	for entry in Catalog.games_with_stats():
		var row := UI.hbox(12)
		row.add_child(UI.image(Catalog.texture(str(entry["cover"])), Vector2(72, 46), 8))
		row.add_child(UI.expand(UI.fit(UI.label(str(entry["title"]), 15, UI.TEXT, true))))
		var playable := bool(entry["playable"])
		var play := UI.button("Oyna" if playable else "Yakında", "primary" if playable else "ghost", 13, 38)
		play.custom_minimum_size.x = 92
		play.disabled = not playable
		play.pressed.connect(func(): play_requested.emit(str(entry["id"])))
		row.add_child(play)
		_quick_list.add_child(row)
		_quick_list.add_child(UI.divider())
	if _quick_list.get_child_count() > 0:
		_quick_list.get_child(-1).queue_free()


# ------------------------------------------------------------------ toolbar + grid

func _build_toolbar() -> Control:
	_toolbar = BoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 10)
	var segments := UI.hbox(0)
	_toolbar.add_child(segments)
	var bar := UI.hbox(10)
	_toolbar.add_child(UI.expand(bar))
	for entry in FILTERS:
		var segment := UI.segment(str(entry[1]), str(entry[2]), entry[0] == _filter)
		segment.pressed.connect(func():
			_filter = str(entry[0])
			_render_filters()
			_render_grid()
		)
		segments.add_child(segment)
		_filter_buttons[entry[0]] = segment
	bar.add_child(UI.spacer())
	var search := UI.search_field("Kütüphanede ara...", 42)
	search.custom_minimum_size.x = 200
	search.text_changed.connect(set_query)
	bar.add_child(search)
	var sort := OptionButton.new()
	sort.focus_mode = Control.FOCUS_NONE
	sort.custom_minimum_size = Vector2(170, 42)
	sort.add_theme_font_size_override("font_size", 13)
	for label_text in SORTS:
		sort.add_item(label_text)
	var sort_style := UI.box(Color(UI.SURFACE, 0.9), 10, UI.BORDER, 1)
	sort_style.content_margin_left = 14
	for state in ["normal", "hover", "pressed"]:
		sort.add_theme_stylebox_override(state, sort_style)
	sort.item_selected.connect(func(index: int):
		_sort = index
		_render_grid()
	)
	bar.add_child(sort)
	_grid_button = UI.icon_button("grid", "Izgara görünümü", 42, UI.TEXT_2, true)
	_list_button = UI.icon_button("list", "Liste görünümü", 42, UI.TEXT_2, true)
	_grid_button.pressed.connect(_set_view.bind(false))
	_list_button.pressed.connect(_set_view.bind(true))
	bar.add_child(_grid_button)
	bar.add_child(_list_button)
	_set_view(false)
	return _toolbar


func _set_view(list_view: bool) -> void:
	_list_view = list_view
	_grid_button.add_theme_color_override("icon_normal_color", UI.ACCENT if not list_view else UI.TEXT_2)
	_list_button.add_theme_color_override("icon_normal_color", UI.ACCENT if list_view else UI.TEXT_2)
	if _grid != null:
		apply_layout(_content_width)
		_render_grid()


func _render_filters() -> void:
	for entry in FILTERS:
		var segment := _filter_buttons[entry[0]] as Button
		segment.text = "%s (%d)" % [entry[1], _count(str(entry[0]))]
		segment.set_pressed_no_signal(entry[0] == _filter)


func _render_grid() -> void:
	UI.clear(_grid)
	var games := _games()
	if games.is_empty():
		var empty := UI.panel(18)
		empty.custom_minimum_size = Vector2(minf(_content_width, 560.0), 170)
		var messages := {
			"installed": "Yüklü oyun yok",
			"recent": "Henüz oyun oynamadın",
			"favorites": "Favori oyunun yok — kartlardaki ☆ ile ekleyebilirsin",
		}
		empty.add_child(UI.empty_state("gamepad", messages.get(_filter, "Aramana uyan oyun yok")))
		_grid.add_child(empty)
		return
	for entry in games:
		_grid.add_child(_list_row(entry) if _list_view else _card(entry))


func _status_pill(entry: Dictionary) -> Control:
	var state: Array = Catalog.status(str(entry["id"]))
	var color: Color = {"green": UI.GREEN, "amber": UI.AMBER, "muted": UI.TEXT_3}[state[2]]
	return UI.pill(str(state[0]), color, str(state[1]), 12, state[2] == "green")


func _star(entry: Dictionary) -> Button:
	var favorite := bool(entry["favorite"])
	var star := UI.icon_button("star_fill" if favorite else "star", "Favorilere ekle", 34, UI.ACCENT if favorite else UI.TEXT, true)
	star.add_theme_stylebox_override("normal", UI.box(Color(UI.BG, 0.6), 9, Color(1, 1, 1, 0.15), 1))
	star.pressed.connect(func():
		var added := Catalog.toggle_favorite(str(entry["id"]))
		toast.emit("%s favorilere %s." % [str(entry["title"]), "eklendi" if added else "çıkarıldı"])
		refresh()
	)
	return star


func _more(entry: Dictionary) -> Button:
	var more := UI.icon_button("dots_h", "Seçenekler", 34, UI.TEXT_2, true)
	more.pressed.connect(func():
		_menu_game = str(entry["id"])
		_game_menu.clear()
		_game_menu.add_item("Oyna", 0)
		_game_menu.set_item_disabled(0, not bool(entry["playable"]))
		_game_menu.add_item("Favorilerden çıkar" if bool(entry["favorite"]) else "Favorilere ekle", 1)
		var rect := more.get_global_rect()
		_game_menu.popup(Rect2i(Vector2i(rect.position + Vector2(0, rect.size.y + 4)), Vector2i.ZERO))
	)
	return more


func _on_menu(id: int) -> void:
	match id:
		0: play_requested.emit(_menu_game)
		1:
			Catalog.toggle_favorite(_menu_game)
			refresh()


func _genre_chips(entry: Dictionary) -> HBoxContainer:
	var row := UI.hbox(6)
	for genre in entry["genres"]:
		var chip := UI.panel(0, UI.box(Color(1, 1, 1, 0.06), 6, UI.BORDER, 1, 4))
		(chip.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 8
		(chip.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 8
		chip.add_child(UI.label(str(genre), 11, UI.TEXT_2))
		row.add_child(chip)
	return row


func _card(entry: Dictionary) -> Control:
	var card := UI.panel(0, UI.card_style(0))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(0)
	card.add_child(column)
	var art := UI.image(Catalog.texture(str(entry["cover"])), Vector2(0, 160), 12)
	art.add_child(UI.shade(0.9))
	var art_layer := UI.vbox(0)
	art_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UI.hbox(0)
	top.add_child(_star(entry))
	art_layer.add_child(top)
	art_layer.add_child(UI.vspacer())
	art_layer.add_child(UI.fit(UI.label(str(entry["title"]), 17, UI.TEXT, true)))
	art.add_child(UI.margin(art_layer, 10, 10, 10, 8))
	column.add_child(art)
	var info := UI.vbox(10)
	column.add_child(UI.margin(info, 12, 8, 12, 12))
	info.add_child(_genre_chips(entry))
	var bottom := UI.hbox(8)
	bottom.add_child(_status_pill(entry))
	bottom.add_child(UI.spacer())
	bottom.add_child(_more(entry))
	info.add_child(bottom)
	return card


func _list_row(entry: Dictionary) -> Control:
	var card := UI.panel(10)
	var row := UI.hbox(14)
	card.add_child(row)
	row.add_child(UI.image(Catalog.texture(str(entry["cover"])), Vector2(110, 62), 8))
	var text := UI.vbox(6)
	UI.expand(text)
	text.add_child(UI.fit(UI.label(str(entry["title"]), 16, UI.TEXT, true)))
	text.add_child(_genre_chips(entry))
	row.add_child(text)
	row.add_child(UI.label(Catalog.ago(int(entry["last_played"])), 12, UI.TEXT_3))
	row.add_child(_status_pill(entry))
	row.add_child(_star(entry))
	var play := UI.button("Oyna", "primary", 13, 36)
	play.disabled = not bool(entry["playable"])
	play.pressed.connect(func(): play_requested.emit(str(entry["id"])))
	row.add_child(play)
	row.add_child(_more(entry))
	return card


# ------------------------------------------------------------------ bottom

func _build_recent() -> Control:
	var card := UI.panel(16)
	UI.expand(card, 1.6)
	var column := UI.vbox(12)
	card.add_child(column)
	var header := UI.section_header("Son Oynananlar", "Tümünü Gör", 20)
	(header.get_node("Link") as Button).pressed.connect(func():
		_filter = "recent"
		_render_filters()
		_render_grid()
	)
	column.add_child(header)
	_recent_row = UI.hbox(12)
	column.add_child(_recent_row)
	return card


func _render_recent() -> void:
	UI.clear(_recent_row)
	var recent := Catalog.recent_games()
	if recent.is_empty():
		_recent_row.add_child(UI.expand(UI.empty_state("clock", "Henüz oyun oynamadın", "Oynadığın oyunlar burada görünecek.", true)))
		return
	for entry in recent.slice(0, 4):
		var art := UI.image(Catalog.texture(str(entry["cover"])), Vector2(0, 110), 10)
		UI.expand(art)
		art.add_child(UI.shade(0.95))
		var text := UI.vbox(0)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(UI.vspacer())
		text.add_child(UI.fit(UI.label(str(entry["title"]), 14, UI.TEXT, true)))
		text.add_child(UI.label(Catalog.ago(int(entry["last_played"])), 12, UI.TEXT_2))
		art.add_child(UI.margin(text, 10, 8, 10, 8))
		_recent_row.add_child(art)


func _build_continue() -> Control:
	var card := UI.panel(16)
	var column := UI.vbox(12)
	card.add_child(column)
	column.add_child(UI.section_header("Devam Et", "", 20))
	_continue_list = UI.vbox(10)
	column.add_child(_continue_list)
	return card


func _render_continue() -> void:
	UI.clear(_continue_list)
	var recent := Catalog.recent_games().filter(func(g): return g["playable"])
	if recent.is_empty():
		_continue_list.add_child(UI.empty_state("play", "Devam edilecek oyun yok", "", true))
		return
	var longest := 1
	for entry in recent:
		longest = maxi(longest, int(entry["playtime"]))
	for entry in recent.slice(0, 2):
		var row := UI.hbox(12)
		row.add_child(UI.image(Catalog.texture(str(entry["cover"])), Vector2(110, 58), 8))
		var text := UI.vbox(4)
		UI.expand(text)
		text.add_child(UI.fit(UI.label(str(entry["title"]), 14, UI.TEXT, true)))
		text.add_child(UI.fit(UI.label("%s oynandı  •  %s" % [Catalog.hours(int(entry["playtime"])), Catalog.ago(int(entry["last_played"]))], 12, UI.TEXT_2)))
		text.add_child(UI.progress(float(entry["playtime"]) / float(longest), UI.ACCENT, 4))
		row.add_child(text)
		var play := UI.button("Oyna", "primary", 13, 38)
		play.custom_minimum_size.x = 88
		play.pressed.connect(func(): play_requested.emit(str(entry["id"])))
		row.add_child(play)
		_continue_list.add_child(row)
