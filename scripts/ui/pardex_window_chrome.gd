extends Node

const RETRY_SECONDS := 0.15
const CHROME_SCENE := preload("res://scenes/ui/window_chrome.tscn")

var _bound := false
var _header: Control
var _header_row: HBoxContainer
var _chrome: HBoxContainer

func _ready() -> void:
	call_deferred("_bind")

func _bind() -> void:
	if _bound:
		return
	var scene := get_tree().current_scene
	if scene == null or scene.name != "Pardex":
		_retry()
		return
	_header = scene.get_node_or_null("MainMargin/MainVBox/Header") as Control
	_header_row = scene.get_node_or_null("MainMargin/MainVBox/Header/HeaderRow") as HBoxContainer
	if _header == null or _header_row == null:
		_retry()
		return

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	_chrome = CHROME_SCENE.instantiate() as HBoxContainer
	_header_row.add_child(_chrome)

	var minimize := _chrome.get_node("MinimizeButton") as Button
	var maximize := _chrome.get_node("MaximizeButton") as Button
	var close := _chrome.get_node("CloseButton") as Button
	minimize.pressed.connect(_minimize_window)
	maximize.pressed.connect(_toggle_maximize)
	close.pressed.connect(func(): get_tree().quit())
	_header.gui_input.connect(_on_header_gui_input)

	_bound = true
	call_deferred("_place_notification_button")

func _retry() -> void:
	get_tree().create_timer(RETRY_SECONDS).timeout.connect(_bind)

func _place_notification_button() -> void:
	if not _bound or _header_row == null or _chrome == null:
		return
	var notification := _header_row.get_node_or_null("NotificationButton") as Button
	if notification == null:
		get_tree().create_timer(0.20).timeout.connect(_place_notification_button)
		return
	notification.text = "🔔"
	notification.custom_minimum_size = Vector2(44, 44)
	notification.add_theme_font_size_override("font_size", 16)
	notification.add_theme_color_override("font_color", Color(0.72, 0.86, 1.0, 1.0))
	_header_row.move_child(notification, _chrome.get_index())

func _minimize_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

func _toggle_maximize() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			DisplayServer.window_start_drag()
