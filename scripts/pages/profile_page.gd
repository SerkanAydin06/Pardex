extends VBoxContainer

# Profil: banner, identity, headline stats and the "Genel Bakış" overview.
# Name, presence and friend count come from PARDEX; games and sessions from the
# local play history. Level, achievements and badges have no backend yet, so
# they show their empty state instead of invented numbers.

signal navigate(page: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")
const TABS := ["Genel Bakış", "Başarımlar", "Oyunlar", "Aktivite", "Rozetler", "İstatistikler"]

var display_name := "Pardus"

var _name_label: Label
var _status_label: Label
var _avatar_holder: Control
var _stats_row: HBoxContainer
var _tab_buttons: Array[Button] = []
var _tab := 0
var _content: Control
var _overview: BoxContainer
var _content_width := 1000.0


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body := UI.vbox(14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	body.add_child(_build_banner())

	var profile_card := UI.panel(0, UI.box(UI.SURFACE, 12, UI.BORDER, 1, 0))
	body.add_child(profile_card)
	var profile_column := UI.vbox(0)
	profile_card.add_child(profile_column)
	_stats_row = UI.hbox(0)
	var stats_margin := MarginContainer.new()
	for side in ["left", "right"]:
		stats_margin.add_theme_constant_override("margin_" + side, 16)
	stats_margin.add_theme_constant_override("margin_top", 12)
	stats_margin.add_theme_constant_override("margin_bottom", 10)
	stats_margin.add_child(_stats_row)
	profile_column.add_child(stats_margin)
	var divider := ColorRect.new()
	divider.color = UI.BORDER
	divider.custom_minimum_size.y = 1
	profile_column.add_child(divider)
	var tabs := UI.hbox(2)
	var tabs_margin := MarginContainer.new()
	tabs_margin.add_theme_constant_override("margin_left", 10)
	tabs_margin.add_child(tabs)
	profile_column.add_child(tabs_margin)
	for index in TABS.size():
		var tab_button := _tab_button(TABS[index])
		tab_button.pressed.connect(_select_tab.bind(index))
		tabs.add_child(tab_button)
		_tab_buttons.append(tab_button)

	_content = UI.vbox(14)
	body.add_child(_content)

	PardexOnline.presence_changed.connect(func(_p): _render_identity())
	PardexOnline.connection_state_changed.connect(func(_s): _render_identity())
	PardexOnline.social_state_changed.connect(func(_s): refresh())
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh())
	refresh()


func refresh() -> void:
	_render_identity()
	_render_stats()
	_select_tab(_tab)


func apply_layout(content_width: float) -> void:
	_content_width = content_width
	if _overview != null:
		_overview.vertical = content_width < 820.0


func _build_banner() -> Control:
	var banner := UI.image(Catalog.texture("res://assets/ui/top_banner.png"), Vector2(0, 170), 12)
	banner.add_child(UI.shade(0.95, true))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	banner.add_child(margin)
	var row := UI.hbox(18)
	margin.add_child(row)
	_avatar_holder = CenterContainer.new()
	row.add_child(_avatar_holder)
	var text := UI.vbox(4)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.expand(text)
	row.add_child(text)
	var name_row := UI.hbox(8)
	text.add_child(name_row)
	_name_label = UI.label("", 26, UI.TEXT, true)
	name_row.add_child(_name_label)
	_status_label = UI.label("", 13, UI.GREEN)
	text.add_child(_status_label)
	text.add_child(UI.label("“Oyunlar daha güzel, birlikte oynayınca.”", 12, UI.TEXT_2))
	var edit := UI.button("Profili Düzenle", "ghost", 12, 34)
	var edit_style := UI.box(Color(UI.BG, 0.8), 8, UI.BORDER_HI, 1)
	edit_style.content_margin_left = 16
	edit_style.content_margin_right = 16
	edit.add_theme_stylebox_override("normal", edit_style)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.pressed.connect(func(): navigate.emit("settings"))
	row.add_child(edit)

	var level := UI.panel(12, UI.box(Color(UI.BG, 0.75), 12, UI.BORDER_HI, 1, 12))
	level.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level.custom_minimum_size.x = 190
	var level_row := UI.hbox(12)
	level.add_child(level_row)
	var badge := Label.new()
	badge.text = "—"
	badge.custom_minimum_size = Vector2(48, 48)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", UI.GOLD)
	badge.add_theme_stylebox_override("normal", UI.box(Color.TRANSPARENT, 24, UI.GOLD, 3))
	level_row.add_child(badge)
	var level_text := UI.vbox(4)
	UI.expand(level_text)
	level_text.alignment = BoxContainer.ALIGNMENT_CENTER
	level_text.add_child(UI.label("Seviye", 12, UI.TEXT, true))
	level_text.add_child(UI.progress(0.0, UI.ACCENT, 5))
	level_text.add_child(UI.label("Seviye sistemi yakında", 10, UI.TEXT_3))
	level_row.add_child(level_text)
	row.add_child(level)
	return banner


func _render_identity() -> void:
	if _name_label == null:
		return
	_name_label.text = display_name
	UI.clear(_avatar_holder)
	var presence := PardexOnline.effective_presence if PardexOnline.is_online() else "offline"
	_avatar_holder.add_child(UI.avatar(display_name, 104, presence, UI.ACCENT))
	_status_label.text = "●  " + UI.presence_label(presence)
	_status_label.add_theme_color_override("font_color", UI.presence_color(presence))


func _render_stats() -> void:
	UI.clear(_stats_row)
	var friends = PardexOnline.social_state.get("friends", [])
	var friend_count := (friends as Array).size() if typeof(friends) == TYPE_ARRAY else 0
	for stat in [
		[str(Catalog.GAMES.size()), "Oyun"],
		["0", "Başarım Puanı"],
		["0", "Rozet"],
		[str(friend_count), "Arkadaş"],
	]:
		var cell := UI.vbox(0)
		UI.expand(cell)
		var value := UI.label(str(stat[0]), 18, UI.TEXT, true)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(value)
		var caption := UI.label(str(stat[1]), 11, UI.TEXT_3)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(caption)
		_stats_row.add_child(cell)


func _tab_button(text: String) -> Button:
	var item := Button.new()
	item.text = text
	item.toggle_mode = true
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size.y = 40
	item.add_theme_font_size_override("font_size", 13)
	var normal := UI.box(Color.TRANSPARENT, 0)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var active := normal.duplicate() as StyleBoxFlat
	active.border_color = UI.ACCENT
	active.border_width_bottom = 2
	for state in ["normal", "hover"]:
		item.add_theme_stylebox_override(state, normal)
	for state in ["pressed", "hover_pressed"]:
		item.add_theme_stylebox_override(state, active)
	item.add_theme_color_override("font_color", UI.TEXT_2)
	item.add_theme_color_override("font_hover_color", UI.TEXT)
	item.add_theme_color_override("font_pressed_color", UI.ACCENT)
	item.add_theme_color_override("font_hover_pressed_color", UI.ACCENT)
	return item


func _select_tab(index: int) -> void:
	_tab = index
	for button_index in _tab_buttons.size():
		_tab_buttons[button_index].set_pressed_no_signal(button_index == index)
	UI.clear(_content)
	_overview = null
	match index:
		0:
			_overview = BoxContainer.new()
			_overview.add_theme_constant_override("separation", 14)
			_overview.add_child(UI.expand(_recent_card(), 1.0))
			_overview.add_child(UI.expand(_achievements_card(), 1.0))
			_overview.add_child(UI.expand(_stats_card(), 1.0))
			_content.add_child(_overview)
			apply_layout(_content_width)
		2:
			_content.add_child(_recent_card())
		5:
			_content.add_child(_stats_card())
		_:
			var card := UI.panel(18)
			card.custom_minimum_size.y = 200
			card.add_child(UI.empty_state("◇", "%s yakında" % TABS[index], "Bu bölüm PARDEX hesap sistemiyle birlikte gelecek."))
			_content.add_child(card)


func _recent_card() -> Control:
	var card := UI.panel(14)
	var column := UI.vbox(10)
	card.add_child(column)
	column.add_child(UI.section_header("Son Oynanan Oyunlar", "", 14))
	var recent := Catalog.recent_games()
	if recent.is_empty():
		column.add_child(UI.empty_state("▶", "Henüz oyun oynamadın", "Oynadığın oyunlar burada listelenir."))
		return card
	var most := 1
	for entry in recent:
		most = maxi(most, int(entry["launches"]))
	for entry in recent:
		var row := UI.hbox(10)
		row.add_child(UI.image(Catalog.texture(str(entry["cover"])), Vector2(52, 38), 6))
		var text := UI.vbox(3)
		UI.expand(text)
		text.add_child(UI.label(str(entry["title"]), 13, UI.TEXT, true))
		text.add_child(UI.label("%d oturum  •  %s" % [int(entry["launches"]), Catalog.last_played_text(int(entry["last_played"]))], 10, UI.TEXT_3))
		text.add_child(UI.progress(float(entry["launches"]) / float(most), UI.ACCENT, 4))
		row.add_child(text)
		column.add_child(row)
	return card


func _achievements_card() -> Control:
	var card := UI.panel(14)
	var column := UI.vbox(10)
	card.add_child(column)
	column.add_child(UI.section_header("Başarımlar", "", 14))
	column.add_child(_badge_row(5))
	column.add_child(UI.label("0 başarım açıldı  •  Başarımlar yakında", 11, UI.TEXT_3))
	column.add_child(UI.progress(0.0, UI.ACCENT, 5))
	column.add_child(UI.label("Öne Çıkan Rozetler", 13, UI.TEXT, true))
	column.add_child(_badge_row(4))
	return card


func _badge_row(count: int) -> HBoxContainer:
	var row := UI.hbox(8)
	for _index in count:
		var badge := Label.new()
		badge.text = "⬡"
		badge.custom_minimum_size = Vector2(40, 40)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 22)
		badge.add_theme_color_override("font_color", Color(UI.TEXT_3, 0.6))
		badge.add_theme_stylebox_override("normal", UI.box(UI.SURFACE_2, 8, UI.BORDER, 1))
		badge.tooltip_text = "Kilitli"
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(badge)
	return row


func _stats_card() -> Control:
	var card := UI.panel(14)
	var column := UI.vbox(12)
	card.add_child(column)
	var header := UI.hbox(8)
	header.add_child(UI.expand(UI.label("Oyun İstatistikleri", 14, UI.TEXT, true)))
	header.add_child(UI.tag("Bu bilgisayar", UI.ACCENT))
	column.add_child(header)
	var recent := Catalog.recent_games()
	var sessions := 0
	for entry in recent:
		sessions += int(entry["launches"])
	var friends = PardexOnline.social_state.get("friends", [])
	for stat in [
		["▶", "Oyun oturumu", str(sessions)],
		["◈", "Oynanan oyun", str(recent.size())],
		["☆", "Başarım", "0"],
		["☺", "Arkadaş", str((friends as Array).size() if typeof(friends) == TYPE_ARRAY else 0)],
	]:
		var row := UI.hbox(12)
		var icon := UI.label(str(stat[0]), 15, UI.TEXT_2)
		icon.custom_minimum_size.x = 22
		row.add_child(icon)
		var text := UI.vbox(0)
		UI.expand(text)
		text.add_child(UI.label(str(stat[1]), 11, UI.TEXT_3))
		text.add_child(UI.label(str(stat[2]), 15, UI.TEXT, true))
		row.add_child(text)
		column.add_child(row)
	return card
