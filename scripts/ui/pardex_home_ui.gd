extends Node

# PARDEX Ana Sayfa katmanı.
# Görsel/oyun assetleri bilerek kullanılmıyor; bu sahne referans mockup'taki
# yerleşim, boş durumlar ve görsel dili üretir. Oyunlar geldikçe kartlar
# veri ile doldurulabilir.

const RETRY_SECONDS := 0.20

var _main: Control
var _main_vbox: VBoxContainer
var _header: Control
var _header_text: Control
var _search: LineEdit
var _connection_pill: Control
var _library_button: Button
var _friends_button: Button
var _rooms_button: Button
var _settings_button: Button
var _exit_button: Button
var _home_button: Button
var _home_content: VBoxContainer
var _selected_style: StyleBox
var _normal_style: StyleBox
var _bound := false


func _ready() -> void:
	call_deferred("_bind_ui")


func _bind_ui() -> void:
	if _bound:
		return
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null or scene.name != "Pardex":
		_retry_bind()
		return

	_main = scene as Control
	_main_vbox = _main.get_node_or_null("MainMargin/MainVBox") as VBoxContainer
	_header = _main.get_node_or_null("MainMargin/MainVBox/Header") as Control
	_header_text = _main.get_node_or_null("MainMargin/MainVBox/Header/HeaderRow/HeaderText") as Control
	_search = _main.get_node_or_null("MainMargin/MainVBox/Header/HeaderRow/LibrarySearch") as LineEdit
	_connection_pill = _main.get_node_or_null("MainMargin/MainVBox/Header/HeaderRow/ConnectionPill") as Control
	_library_button = _main.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox/LibraryButton") as Button
	_friends_button = _main.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox/FriendsButton") as Button
	_rooms_button = _main.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox/RoomsButton") as Button
	_settings_button = _main.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox/SettingsButton") as Button
	_exit_button = _main.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox/ExitButton") as Button

	if _main_vbox == null or _header == null or _search == null or _library_button == null or _friends_button == null:
		_retry_bind()
		return

	_selected_style = _library_button.get_theme_stylebox("normal")
	_normal_style = _friends_button.get_theme_stylebox("normal")
	_create_home_button()
	_create_home_content()
	_wire_navigation()
	_bound = true
	_show_home()


func _retry_bind() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(RETRY_SECONDS)
	timer.timeout.connect(_bind_ui)


func _create_home_button() -> void:
	var sidebar := _library_button.get_parent()
	_home_button = Button.new()
	_home_button.name = "HomeButton"
	_home_button.text = "⌂  Ana Sayfa"
	_home_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_home_button.focus_mode = Control.FOCUS_NONE
	_home_button.add_theme_font_size_override("font_size", 15)
	_home_button.add_theme_color_override("font_color", Color(0.96, 0.985, 1.0, 1.0))
	_home_button.add_theme_color_override("font_hover_color", Color(0.96, 0.985, 1.0, 1.0))
	_home_button.add_theme_color_override("font_outline_color", Color(0.0, 0.025, 0.045, 0.95))
	_home_button.add_theme_constant_override("outline_size", 2)
	_home_button.add_theme_stylebox_override("normal", _selected_style)
	_home_button.add_theme_stylebox_override("hover", _selected_style)
	sidebar.add_child(_home_button)
	sidebar.move_child(_home_button, _library_button.get_index())


func _wire_navigation() -> void:
	_home_button.pressed.connect(_show_home)
	for button in [_library_button, _friends_button, _rooms_button, _settings_button, _exit_button]:
		if button != null:
			button.pressed.connect(_leave_home)
	_home_button.mouse_entered.connect(_on_home_hover.bind(true))
	_home_button.mouse_exited.connect(_on_home_hover.bind(false))


func _on_home_hover(hovered: bool) -> void:
	if _home_content != null and _home_content.visible:
		return
	_home_button.modulate = Color(1.05, 1.05, 1.05, 1.0) if hovered else Color.WHITE


func _create_home_content() -> void:
	_home_content = VBoxContainer.new()
	_home_content.name = "HomeContent"
	_home_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home_content.add_theme_constant_override("separation", 14)
	_main_vbox.add_child(_home_content)
	_main_vbox.move_child(_home_content, _header.get_index() + 1)

	var top_row := HBoxContainer.new()
	top_row.custom_minimum_size = Vector2(0, 310)
	top_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_row.add_theme_constant_override("separation", 14)
	_home_content.add_child(top_row)

	var hero := _build_hero()
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.size_flags_stretch_ratio = 2.0
	top_row.add_child(hero)

	var agenda := _build_agenda()
	agenda.custom_minimum_size = Vector2(360, 0)
	agenda.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agenda.size_flags_stretch_ratio = 1.0
	top_row.add_child(agenda)

	var bottom_row := HBoxContainer.new()
	bottom_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_row.add_theme_constant_override("separation", 14)
	_home_content.add_child(bottom_row)

	var recent := _build_recent()
	recent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recent.size_flags_stretch_ratio = 2.0
	bottom_row.add_child(recent)

	var quick := _build_quick_start()
	quick.custom_minimum_size = Vector2(360, 0)
	quick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick.size_flags_stretch_ratio = 1.0
	bottom_row.add_child(quick)


func _build_hero() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "HomeHero"
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.008, 0.035, 0.065, 1.0), Color(0.08, 0.34, 0.50, 0.95), 16))

	var base := ColorRect.new()
	base.color = Color(0.01, 0.04, 0.075, 1.0)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(base)

	var mark := Label.new()
	mark.text = "P"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.offset_left = 430.0
	mark.offset_top = -28.0
	mark.add_theme_font_size_override("font_size", 210)
	mark.add_theme_color_override("font_color", Color(0.10, 0.45, 0.82, 0.18))
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(mark)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var tag := Label.new()
	tag.text = "  ANA SAYFA  "
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", Color(0.18, 0.82, 1.0, 1.0))
	column.add_child(tag)

	var title := Label.new()
	title.text = "PARDEX'e Hoş Geldin"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.97, 0.985, 1.0, 1.0))
	column.add_child(title)

	var body := Label.new()
	body.text = "Oyunların, arkadaşların ve güncellemelerin\nburada görünecek."
	body.add_theme_font_size_override("font_size", 17)
	body.add_theme_color_override("font_color", Color(0.74, 0.82, 0.92, 1.0))
	column.add_child(body)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)

	var library_action := Button.new()
	library_action.text = "Kütüphaneye Git"
	library_action.custom_minimum_size = Vector2(190, 48)
	library_action.focus_mode = Control.FOCUS_NONE
	library_action.add_theme_font_size_override("font_size", 15)
	library_action.add_theme_color_override("font_color", Color(0.015, 0.08, 0.12, 1.0))
	library_action.add_theme_stylebox_override("normal", _button_style(Color(0.06, 0.70, 0.96, 1.0), Color(0.28, 0.86, 1.0, 1.0)))
	library_action.add_theme_stylebox_override("hover", _button_style(Color(0.10, 0.79, 1.0, 1.0), Color(0.52, 0.94, 1.0, 1.0)))
	library_action.pressed.connect(func(): _library_button.emit_signal("pressed"))
	actions.add_child(library_action)

	var details := Button.new()
	details.text = "Detaylar"
	details.custom_minimum_size = Vector2(150, 48)
	details.focus_mode = Control.FOCUS_NONE
	details.add_theme_font_size_override("font_size", 15)
	details.add_theme_color_override("font_color", Color(0.84, 0.90, 0.98, 1.0))
	details.add_theme_stylebox_override("normal", _button_style(Color(0.035, 0.075, 0.12, 0.94), Color(0.12, 0.30, 0.44, 1.0)))
	details.add_theme_stylebox_override("hover", _button_style(Color(0.05, 0.12, 0.18, 1.0), Color(0.18, 0.50, 0.68, 1.0)))
	actions.add_child(details)

	var dots := Label.new()
	dots.text = "●  •  •  •"
	dots.add_theme_font_size_override("font_size", 15)
	dots.add_theme_color_override("font_color", Color(0.14, 0.71, 0.95, 0.95))
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(dots)
	return panel


func _build_agenda() -> PanelContainer:
	var panel := _card_panel()
	var margin := _card_margin(panel, 18)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_section_title("Bugünün Gündemi"))
	column.add_child(_agenda_row("◖", "Platform Hazırlanıyor", "Ana yapı oluşturuldu, içerikler yakında eklenecek.", "Şimdi", Color(0.18, 0.54, 0.95, 1.0)))
	column.add_child(_agenda_row("●", "Sosyal Özellikler Aktif", "Arkadaşlar, davetler ve sohbet hazır.", "Bugün", Color(0.48, 0.36, 0.96, 1.0)))
	column.add_child(_agenda_row("+", "Yeni Oyunlar Yakında", "Oyun kartları üretildikçe ana sayfada görünecek.", "Yakında", Color(0.14, 0.52, 0.92, 1.0)))

	var more := Label.new()
	more.text = "Tüm Haberler  →"
	more.add_theme_font_size_override("font_size", 13)
	more.add_theme_color_override("font_color", Color(0.12, 0.77, 1.0, 1.0))
	more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(more)
	return panel


func _agenda_row(icon_text: String, title_text: String, body_text: String, when_text: String, accent: Color) -> PanelContainer:
	var row_panel := PanelContainer.new()
	row_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.007, 0.027, 0.048, 0.86), Color(0.055, 0.15, 0.23, 0.9), 11))
	var margin := _card_margin(row_panel, 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(56, 56)
	icon_box.add_theme_stylebox_override("panel", _panel_style(Color(accent.r * 0.24, accent.g * 0.24, accent.b * 0.24, 1.0), Color(accent.r, accent.g, accent.b, 0.70), 9))
	var icon := Label.new()
	icon.text = icon_text
	icon.add_theme_font_size_override("font_size", 24)
	icon.add_theme_color_override("font_color", accent)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_box.add_child(icon)
	row.add_child(icon_box)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 3)
	row.add_child(texts)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	texts.add_child(title)
	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 11)
	body.add_theme_color_override("font_color", Color(0.62, 0.70, 0.80, 1.0))
	texts.add_child(body)

	var when := Label.new()
	when.text = when_text
	when.custom_minimum_size = Vector2(58, 0)
	when.add_theme_font_size_override("font_size", 11)
	when.add_theme_color_override("font_color", Color(0.58, 0.66, 0.77, 1.0))
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(when)
	return row_panel


func _build_recent() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	section.add_child(header)
	var title := _section_title("Son Oynananlar")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var more := Label.new()
	more.text = "Tümünü Gör  →"
	more.add_theme_color_override("font_color", Color(0.12, 0.77, 1.0, 1.0))
	more.add_theme_font_size_override("font_size", 13)
	header.add_child(more)

	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 10)
	section.add_child(cards)
	cards.add_child(_empty_game_card("⌁", "Henüz oyun yok"))
	cards.add_child(_empty_game_card("○", "Boş Slot"))
	cards.add_child(_empty_game_card("▦", "Boş Slot"))
	cards.add_child(_empty_game_card("+", "Boş Slot"))
	return section


func _empty_game_card(icon_text: String, title_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(150, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.008, 0.035, 0.065, 0.92), Color(0.075, 0.26, 0.39, 0.95), 12))
	var margin := _card_margin(panel, 14)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	var art := Label.new()
	art.text = icon_text
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.add_theme_font_size_override("font_size", 42)
	art.add_theme_color_override("font_color", Color(0.30, 0.54, 0.82, 0.78))
	art.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	art.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(art)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0, 1.0))
	column.add_child(title)
	var body := Label.new()
	body.text = "Oyunlar eklendiğinde\nburada görünecek."
	body.add_theme_font_size_override("font_size", 11)
	body.add_theme_color_override("font_color", Color(0.57, 0.66, 0.77, 1.0))
	column.add_child(body)
	return panel


func _build_quick_start() -> PanelContainer:
	var panel := _card_panel()
	var margin := _card_margin(panel, 16)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	column.add_child(_section_title("Hızlı Başlat"))
	for index in range(1, 5):
		column.add_child(_quick_row(index))
	return panel


func _quick_row(index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.008, 0.027, 0.047, 0.88), Color(0.06, 0.16, 0.24, 0.88), 9))
	var margin := _card_margin(panel, 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var icon := Label.new()
	icon.text = "+"
	icon.custom_minimum_size = Vector2(42, 42)
	icon.add_theme_font_size_override("font_size", 23)
	icon.add_theme_color_override("font_color", Color(0.42, 0.58, 0.76, 1.0))
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var title := Label.new()
	title.text = "Oyun Slotu %d" % index
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0, 1.0))
	texts.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Henüz oyun yok."
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.64, 0.75, 1.0))
	texts.add_child(subtitle)
	var soon := Button.new()
	soon.text = "Yakında"
	soon.disabled = true
	soon.custom_minimum_size = Vector2(86, 36)
	soon.add_theme_font_size_override("font_size", 11)
	soon.add_theme_stylebox_override("disabled", _button_style(Color(0.055, 0.10, 0.16, 1.0), Color(0.10, 0.22, 0.34, 1.0)))
	row.add_child(soon)
	return panel


func _show_home() -> void:
	if not _bound:
		return
	for child in _main_vbox.get_children():
		if child is Control:
			(child as Control).visible = (child == _header or child == _home_content)

	if _header_text != null:
		_header_text.hide()
	if _connection_pill != null:
		_connection_pill.hide()
	_search.show()
	_search.placeholder_text = "Oyun, arkadaş veya içerik ara..."
	_search.clear()

	for button in [_library_button, _friends_button, _rooms_button, _settings_button]:
		if button != null:
			button.add_theme_stylebox_override("normal", _normal_style)
			button.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 1.0))
	_home_button.add_theme_stylebox_override("normal", _selected_style)
	_home_button.add_theme_color_override("font_color", Color(0.96, 0.985, 1.0, 1.0))
	_home_button.modulate = Color.WHITE


func _leave_home() -> void:
	if not _bound or _home_content == null:
		return
	_home_content.hide()
	if _header_text != null:
		_header_text.show()
	if _connection_pill != null:
		_connection_pill.show()
	_home_button.add_theme_stylebox_override("normal", _normal_style)
	_home_button.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 1.0))


func _section_title(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.96, 0.975, 1.0, 1.0))
	return label


func _card_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.006, 0.024, 0.043, 0.95), Color(0.06, 0.18, 0.28, 0.95), 13))
	return panel


func _card_margin(panel: PanelContainer, amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", amount)
	margin.add_theme_constant_override("margin_top", amount)
	margin.add_theme_constant_override("margin_right", amount)
	margin.add_theme_constant_override("margin_bottom", amount)
	panel.add_child(margin)
	return margin


func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 3)
	return style


func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style
