extends VBoxContainer

# Kütüphane: hero with library stats, quick start, filter tabs, search, sort,
# grid/list views, recently played and "Devam Et". Install state, favorites,
# last played and playtime are real (catalog + local records).

signal play_requested(game_id: String)
signal details_requested(game_id: String)
signal toast(message: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const LibraryGameCardScene := preload("res://scenes/ui/library_game_card.tscn")
const LibraryListRowScene := preload("res://scenes/ui/library_list_row.tscn")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")
const FILTERS := [["all", "Tümü", ""], ["installed", "Yüklü", "download"], ["recent", "Son Oynanan", "clock"], ["favorites", "Favoriler", "heart"]]

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
var _content_width := 1200.0


func _ready() -> void:
	# Layout is owned by scenes/pages; runtime code only binds data and actions.
	_bind()
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh())
	refresh()


func _bind() -> void:
	_top = %TopRow
	_bottom = %BottomRow
	_stats_row = %StatsRow
	_quick_list = %QuickList
	_toolbar = %Toolbar
	_grid = %GameGrid
	_recent_row = %RecentRow
	_continue_list = %ContinueList
	_grid_button = %GridViewButton
	_list_button = %ListViewButton
	for entry in FILTERS:
		var segment := get_node("%Filter_" + str(entry[0])) as Button
		_filter_buttons[entry[0]] = segment
		segment.pressed.connect(func():
			_filter = str(entry[0])
			_render_filters()
			_render_grid()
		)
	(%SortOption as OptionButton).item_selected.connect(func(index: int):
		_sort = index
		_render_grid()
	)
	_grid_button.pressed.connect(_set_view.bind(false))
	_list_button.pressed.connect(_set_view.bind(true))
	(%RecentLink as Button).pressed.connect(func():
		_filter = "recent"
		_render_filters()
		_render_grid()
	)
	_set_view(false)


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
	_grid.columns = 1 if _list_view else clampi(floori((content_width + 14.0) / 260.0), 2, 6)
	if _toolbar != null:
		_toolbar.vertical = content_width < 1040.0


# ------------------------------------------------------------------ data

func _installed_games() -> Array:
	return Catalog.games_with_stats().filter(func(game): return game["installed"])


func _games() -> Array:
	var games := _installed_games()
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
	var games := _installed_games()
	match kind:
		"installed": return games.filter(func(g): return g["installed"]).size()
		"recent": return games.filter(func(g): return g["last_played"] > 0).size()
		"favorites": return games.filter(func(g): return g["favorite"]).size()
	return games.size()


# ------------------------------------------------------------------ hero

func _render_stats() -> void:
	# Keep the editor-owned tiles, captions, icons and styles; update only data.
	for stat in [["CatalogStat", "all"], ["InstalledStat", "installed"], ["RecentStat", "recent"], ["FavoritesStat", "favorites"]]:
		(_stats_row.get_node("%s/Row/Text/Value" % stat[0]) as Label).text = str(_count(str(stat[1])))


func _wrapped_title(title: String, font_size: int) -> Label:
	var label := UI.label(title, font_size, UI.TEXT, true)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.custom_minimum_size.x = 60
	return label


func _render_quick_start() -> void:
	for child in _quick_list.get_children():
		(child as Control).hide()
	for entry in _installed_games():
		var row := _quick_list.get_node_or_null("Quick_" + str(entry["id"])) as HBoxContainer
		if row == null:
			row = (load("res://scenes/ui/quick_launch_row.tscn") as PackedScene).instantiate() as HBoxContainer
			row.name = "Quick_" + str(entry["id"])
			_quick_list.add_child(row)
		row.show()
		(row.get_node("Artwork/Art") as TextureRect).texture = Catalog.texture(str(entry["cover"]))
		(row.get_node("Title") as Label).text = str(entry["title"])
		var playable := bool(entry["playable"])
		var play := row.get_node("Play") as Button
		play.text = Catalog.action_label(str(entry["id"]))
		play.disabled = not playable
		var callback := _play_quick_game.bind(str(entry["id"]))
		if not play.pressed.is_connected(callback):
			play.pressed.connect(callback)


func _play_quick_game(game_id: String) -> void:
	play_requested.emit(game_id)


# ------------------------------------------------------------------ toolbar + grid

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
		empty.add_child(UI.empty_state("gamepad", messages.get(_filter, "Henüz yüklü oyun yok" if _installed_games().is_empty() else "Aramana uyan oyun yok")))
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


func _genre_chips(entry: Dictionary) -> HBoxContainer:
	var row := UI.hbox(6)
	for genre in entry["genres"]:
		var chip := UI.panel(0, UI.box(Color(1, 1, 1, 0.06), 6, UI.BORDER, 1, 4))
		(chip.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 8
		(chip.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 8
		chip.add_child(UI.label(str(genre), 11, UI.TEXT_2))
		row.add_child(chip)
	return row


# Editor-owned card layouts, populated with live catalog data.
func _on_details_input(event: InputEvent, game_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		details_requested.emit(game_id)


func _card(entry: Dictionary) -> Control:
	var card := LibraryGameCardScene.instantiate() as PanelContainer
	card.gui_input.connect(_on_details_input.bind(str(entry["id"])))
	(card.get_node("Column/Artwork/Art") as TextureRect).texture = Catalog.texture(str(entry["cover"]))
	(card.get_node("Column/Artwork/OverlayMargin/Overlay/Top/StarSlot") as HBoxContainer).add_child(_star(entry))
	(card.get_node("Column/Artwork/OverlayMargin/Overlay/Title") as Label).text = str(entry["title"])
	(card.get_node("Column/InfoMargin/Info/GenreSlot") as HBoxContainer).add_child(_genre_chips(entry))
	(card.get_node("Column/InfoMargin/Info/Bottom/StatusSlot") as HBoxContainer).add_child(_status_pill(entry))
	_bind_play(card.get_node("Column/InfoMargin/Info/Bottom/PlayButton") as Button, entry)
	return card


func _bind_play(button: Button, entry: Dictionary) -> void:
	button.disabled = not bool(entry["installed"])
	button.tooltip_text = str(entry["title"]) + " oyununu başlat"
	button.pressed.connect(func(): play_requested.emit(str(entry["id"])))


func _list_row(entry: Dictionary) -> Control:
	var card := LibraryListRowScene.instantiate() as PanelContainer
	card.gui_input.connect(_on_details_input.bind(str(entry["id"])))
	(card.get_node("Row/Art") as TextureRect).texture = Catalog.texture(str(entry["cover"]))
	(card.get_node("Row/Info/Title") as Label).text = str(entry["title"])
	(card.get_node("Row/Info/GenreSlot") as HBoxContainer).add_child(_genre_chips(entry))
	(card.get_node("Row/LastPlayed") as Label).text = Catalog.ago(int(entry["last_played"]))
	(card.get_node("Row/StatusSlot") as HBoxContainer).add_child(_status_pill(entry))
	(card.get_node("Row/FavoriteSlot") as HBoxContainer).add_child(_star(entry))
	_bind_play(card.get_node("Row/PlayButton") as Button, entry)
	return card



# ------------------------------------------------------------------ bottom

func _render_recent() -> void:
	UI.clear(_recent_row)
	var recent := Catalog.recent_games().filter(func(game): return game["installed"])
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


func _render_continue() -> void:
	UI.clear(_continue_list)
	var recent := Catalog.recent_games().filter(func(game): return game["installed"]).filter(func(g): return g["playable"])
	if recent.is_empty():
		_continue_list.add_child(UI.empty_state("play", "Devam edilecek oyun yok", "", true))
		return
	var longest := 1
	for entry in recent:
		longest = maxi(longest, int(entry["playtime"]))
	for entry in recent.slice(0, 2):
		var row := UI.hbox(12)
		row.add_child(UI.image(Catalog.texture(str(entry["cover"])), Vector2(88, 56), 8))
		var text := UI.vbox(4)
		UI.expand(text)
		text.add_child(_wrapped_title(str(entry["title"]), 14))
		text.add_child(UI.fit(UI.label("%s  •  %s" % [Catalog.hours(int(entry["playtime"])), Catalog.ago(int(entry["last_played"]))], 12, UI.TEXT_2)))
		text.add_child(UI.progress(float(entry["playtime"]) / float(longest), UI.ACCENT, 4))
		row.add_child(text)
		var play := UI.button("Oyna", "primary", 13, 38)
		play.custom_minimum_size.x = 84
		play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		play.pressed.connect(func(): play_requested.emit(str(entry["id"])))
		row.add_child(play)
		_continue_list.add_child(row)
