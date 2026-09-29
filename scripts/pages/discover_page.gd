extends VBoxContainer

# Keşfet: category chips, two featured banners and personal recommendations,
# filtered from the real PARDEX catalog.

signal navigate(page: String)
signal play_requested(game_id: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")

var _category := "Tümü"
var _chips: Array[Button] = []
var _banners: BoxContainer
var _grid: GridContainer
var _grid_width := 800.0


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body := UI.vbox(14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var heading := UI.vbox(2)
	heading.add_child(UI.label("Keşfet", 26, UI.TEXT, true))
	heading.add_child(UI.label("Yeni dünyalar, yeni hikâyeler, sana özel öneriler.", 13, UI.TEXT_2))
	body.add_child(heading)

	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	body.add_child(chips)
	for category in Catalog.CATEGORIES:
		var chip := UI.chip(category, category == _category)
		chip.pressed.connect(_select_category.bind(category))
		chips.add_child(chip)
		_chips.append(chip)

	_banners = BoxContainer.new()
	_banners.add_theme_constant_override("separation", 14)
	body.add_child(_banners)
	_banners.add_child(_banner(Catalog.GAMES[0], "Şimdi İncele", "", 1.7))
	_banners.add_child(_banner(Catalog.GAMES[1], "", "Bu Hafta Öne Çıkanlar", 1.0))

	var header := UI.section_header("Sana Özel Öneriler", "Tümünü Gör  →", 15)
	(header.get_node("Link") as Button).pressed.connect(func(): navigate.emit("library"))
	body.add_child(header)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	body.add_child(_grid)
	_render_grid()


func apply_layout(content_width: float) -> void:
	_banners.vertical = content_width < 760.0
	_grid_width = content_width
	_grid.columns = clampi(floori((content_width + 10.0) / 150.0), 2, 6)


func _select_category(category: String) -> void:
	_category = category
	for chip in _chips:
		chip.set_pressed_no_signal(chip.text == category)
	_render_grid()


func _banner(entry: Dictionary, action_text: String, badge: String, ratio: float) -> Control:
	var frame := UI.image(Catalog.texture(str(entry["banner"])), Vector2(0, 190), 12)
	UI.expand(frame, ratio)
	frame.add_child(UI.shade(0.9, true))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	frame.add_child(margin)
	var column := UI.vbox(6)
	margin.add_child(column)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(push)
	if not badge.is_empty():
		column.add_child(UI.tag(badge, UI.ACCENT))
	column.add_child(UI.label(str(entry["title"]), 22 if action_text.is_empty() else 24, UI.TEXT, true))
	column.add_child(UI.label(str(entry["tagline"]), 12, UI.TEXT_2))
	if not action_text.is_empty():
		var action := UI.button(action_text, "gold", 12, 32)
		action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		action.pressed.connect(_open.bind(entry))
		column.add_child(action)
	var next := UI.icon_button("›", "Sonraki", 30)
	next.add_theme_stylebox_override("normal", UI.box(Color(0, 0, 0, 0.45), 15, Color(1, 1, 1, 0.25), 1))
	next.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	next.offset_left = -44
	next.offset_top = -15
	next.offset_right = -14
	next.offset_bottom = 15
	next.pressed.connect(func(): navigate.emit("library"))
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(overlay)
	overlay.add_child(next)
	return frame


func _render_grid() -> void:
	UI.clear(_grid)
	var matches := Catalog.GAMES.filter(func(entry): return _category == "Tümü" or _category in entry["tags"])
	if matches.is_empty():
		var empty := UI.panel(18)
		empty.custom_minimum_size = Vector2(minf(_grid_width, 520.0), 160)
		empty.add_child(UI.empty_state("◇", "Bu kategoride henüz oyun yok", "Yeni PARDEX oyunları eklendikçe burada görünecek."))
		_grid.add_child(empty)
		return
	for entry in matches:
		_grid.add_child(_poster(entry))


func _poster(entry: Dictionary) -> Control:
	var card := UI.panel(0, UI.box(UI.SURFACE, 10, UI.BORDER, 1))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var art := UI.image(Catalog.texture(str(entry["cover"])), Vector2(0, 150), 10)
	var column := UI.vbox(0)
	card.add_child(column)
	column.add_child(art)
	var info := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		info.add_theme_constant_override("margin_" + side, 8)
	column.add_child(info)
	var text := UI.vbox(1)
	info.add_child(text)
	text.add_child(UI.fit(UI.label(str(entry["title"]), 13, UI.TEXT, true)))
	text.add_child(UI.label(str(entry["genre"]), 10, UI.TEXT_3))
	var open := Button.new()
	open.flat = true
	open.focus_mode = Control.FOCUS_NONE
	open.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	open.tooltip_text = "Oyna" if bool(entry["playable"]) else "Yakında"
	open.pressed.connect(_open.bind(entry))
	card.add_child(open)
	return card


func _open(entry: Dictionary) -> void:
	if bool(entry["playable"]):
		play_requested.emit(str(entry["id"]))
	else:
		navigate.emit("library")
