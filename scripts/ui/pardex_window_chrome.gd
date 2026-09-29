extends Node

const RETRY_SECONDS := 0.15
const CHROME_SCENE := preload("res://scenes/ui/window_chrome.tscn")
const RESIZE_EDGE_SIZE := 7.0
const RESIZE_CORNER_SIZE := 12.0

var _bound := false
var _header: Control
var _header_row: HBoxContainer
var _chrome: HBoxContainer
var _main_scene: Control

func _ready() -> void:
	call_deferred("_bind")

func _bind() -> void:
	if _bound:
		return
	var scene := get_tree().current_scene
	if scene == null or scene.name != "Pardex":
		_retry()
		return
	_main_scene = scene as Control
	_header = scene.get_node_or_null("MainMargin/MainVBox/Header") as Control
	_header_row = scene.get_node_or_null("MainMargin/MainVBox/Header/HeaderRow") as HBoxContainer
	if _main_scene == null or _header == null or _header_row == null:
		_retry()
		return

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
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

	_install_resize_handles()
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

func _install_resize_handles() -> void:
	if _main_scene == null:
		return
	_add_resize_handle("ResizeTop", DisplayServer.WINDOW_EDGE_TOP, Control.CURSOR_VSIZE, Vector2(0, 0), Vector2(1, 0), Vector2(RESIZE_CORNER_SIZE, 0), Vector2(-RESIZE_CORNER_SIZE, RESIZE_EDGE_SIZE))
	_add_resize_handle("ResizeBottom", DisplayServer.WINDOW_EDGE_BOTTOM, Control.CURSOR_VSIZE, Vector2(0, 1), Vector2(1, 1), Vector2(RESIZE_CORNER_SIZE, -RESIZE_EDGE_SIZE), Vector2(-RESIZE_CORNER_SIZE, 0))
	_add_resize_handle("ResizeLeft", DisplayServer.WINDOW_EDGE_LEFT, Control.CURSOR_HSIZE, Vector2(0, 0), Vector2(0, 1), Vector2(0, RESIZE_CORNER_SIZE), Vector2(RESIZE_EDGE_SIZE, -RESIZE_CORNER_SIZE))
	_add_resize_handle("ResizeRight", DisplayServer.WINDOW_EDGE_RIGHT, Control.CURSOR_HSIZE, Vector2(1, 0), Vector2(1, 1), Vector2(-RESIZE_EDGE_SIZE, RESIZE_CORNER_SIZE), Vector2(0, -RESIZE_CORNER_SIZE))
	_add_resize_handle("ResizeTopLeft", DisplayServer.WINDOW_EDGE_TOP_LEFT, Control.CURSOR_FDIAGSIZE, Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), Vector2(RESIZE_CORNER_SIZE, RESIZE_CORNER_SIZE))
	_add_resize_handle("ResizeTopRight", DisplayServer.WINDOW_EDGE_TOP_RIGHT, Control.CURSOR_BDIAGSIZE, Vector2(1, 0), Vector2(1, 0), Vector2(-RESIZE_CORNER_SIZE, 0), Vector2(0, RESIZE_CORNER_SIZE))
	_add_resize_handle("ResizeBottomLeft", DisplayServer.WINDOW_EDGE_BOTTOM_LEFT, Control.CURSOR_BDIAGSIZE, Vector2(0, 1), Vector2(0, 1), Vector2(0, -RESIZE_CORNER_SIZE), Vector2(RESIZE_CORNER_SIZE, 0))
	_add_resize_handle("ResizeBottomRight", DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT, Control.CURSOR_FDIAGSIZE, Vector2(1, 1), Vector2(1, 1), Vector2(-RESIZE_CORNER_SIZE, -RESIZE_CORNER_SIZE), Vector2(0, 0))

func _add_resize_handle(name_value: String, edge, cursor, anchor_from: Vector2, anchor_to: Vector2, offset_from: Vector2, offset_to: Vector2) -> void:
	var handle := Control.new()
	handle.name = name_value
	handle.z_index = 1000
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = cursor
	handle.anchor_left = anchor_from.x
	handle.anchor_top = anchor_from.y
	handle.anchor_right = anchor_to.x
	handle.anchor_bottom = anchor_to.y
	handle.offset_left = offset_from.x
	handle.offset_top = offset_from.y
	handle.offset_right = offset_to.x
	handle.offset_bottom = offset_to.y
	handle.gui_input.connect(_on_resize_handle_input.bind(edge))
	_main_scene.add_child(handle)

func _on_resize_handle_input(event: InputEvent, edge) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			DisplayServer.window_start_resize(edge)
