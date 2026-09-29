extends Node

const RETRY_SECONDS := 0.15

var _bound := false
var _buttons: Array[Button] = []
var _active: Button

func _ready() -> void:
	call_deferred("_bind")

func _bind() -> void:
	if _bound:
		return
	var scene := get_tree().current_scene
	if scene == null or scene.name != "Pardex":
		_retry()
		return
	var sidebar := scene.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox")
	if sidebar == null:
		_retry()
		return
	for button_name in ["HomeButton", "LibraryButton", "FriendsButton", "RoomsButton", "SettingsButton"]:
		var button := sidebar.get_node_or_null(button_name) as Button
		if button == null:
			_retry()
			return
		_buttons.append(button)
		button.pressed.connect(_select.bind(button))
	_bound = true
	_select(_buttons[0])

func _retry() -> void:
	get_tree().create_timer(RETRY_SECONDS).timeout.connect(_bind)

func _select(button: Button) -> void:
	_active = button
	call_deferred("_apply_styles")

func _apply_styles() -> void:
	for button in _buttons:
		var selected := button == _active
		button.add_theme_stylebox_override("normal", _active_style() if selected else _normal_style())
		button.add_theme_stylebox_override("hover", _active_hover_style() if selected else _hover_style())
		button.add_theme_stylebox_override("pressed", _active_hover_style())
		button.add_theme_color_override("font_color", Color(0.96, 0.985, 1.0, 1.0) if selected else Color(0.76, 0.84, 0.93, 1.0))
		button.add_theme_font_size_override("font_size", 16)
		button.custom_minimum_size.y = 56.0

func _active_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.035, 0.20, 0.34, 0.98)
	s.border_color = Color(0.10, 0.46, 0.72, 1.0)
	s.border_width_left = 6
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 14
	s.corner_radius_top_right = 14
	s.corner_radius_bottom_left = 14
	s.corner_radius_bottom_right = 14
	s.content_margin_left = 18
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.shadow_color = Color(0.0, 0.62, 1.0, 0.20)
	s.shadow_size = 9
	return s

func _active_hover_style() -> StyleBoxFlat:
	var s := _active_style()
	s.bg_color = Color(0.045, 0.25, 0.42, 1.0)
	s.border_color = Color(0.12, 0.72, 1.0, 1.0)
	return s

func _normal_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.008, 0.022, 0.038, 0.16)
	s.corner_radius_top_left = 12
	s.corner_radius_top_right = 12
	s.corner_radius_bottom_left = 12
	s.corner_radius_bottom_right = 12
	s.content_margin_left = 24
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

func _hover_style() -> StyleBoxFlat:
	var s := _normal_style()
	s.bg_color = Color(0.025, 0.10, 0.16, 0.92)
	s.border_color = Color(0.08, 0.28, 0.42, 0.95)
	s.border_width_left = 2
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	return s
