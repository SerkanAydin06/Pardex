extends Control

# Borderless desktop window frame, Steam style: the page header drags the
# window, the chrome buttons minimize/maximize/close it and thin invisible
# strips along the edges resize it. Lives in main.tscn above all content.

const APP_ICON := "res://assets/ui/brand_pardex_app_icon.png"
const EDGE := 7.0
const CORNER := 12.0


func _ready() -> void:
	# main.tscn keeps this helper visually empty; it still must be visible so
	# its child resize handles can receive mouse input around the window edges.
	show()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	_apply_app_icon()

	var main := owner as Control
	var chrome := main.get_node("%WindowChrome")
	(chrome.get_node("MinimizeButton") as Button).pressed.connect(
		func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	)
	(chrome.get_node("MaximizeButton") as Button).pressed.connect(_toggle_maximize)
	(chrome.get_node("CloseButton") as Button).pressed.connect(
		func(): main.call("_quit_application")
	)
	var secondary := chrome.get_node_or_null("SecondaryAction") as Button
	if secondary != null:
		secondary.tooltip_text = "PARDEX Ödülleri — yakında"
		secondary.pressed.connect(func(): main.call("_show_toast", "PARDEX Ödülleri yakında."))
	(main.get_node("%Header") as Control).gui_input.connect(_on_header_input)

	_add_edge(DisplayServer.WINDOW_EDGE_TOP, CURSOR_VSIZE, Rect2(CORNER, 0, -CORNER, EDGE), Vector4(0, 0, 1, 0))
	_add_edge(DisplayServer.WINDOW_EDGE_BOTTOM, CURSOR_VSIZE, Rect2(CORNER, -EDGE, -CORNER, 0), Vector4(0, 1, 1, 1))
	_add_edge(DisplayServer.WINDOW_EDGE_LEFT, CURSOR_HSIZE, Rect2(0, CORNER, EDGE, -CORNER), Vector4(0, 0, 0, 1))
	_add_edge(DisplayServer.WINDOW_EDGE_RIGHT, CURSOR_HSIZE, Rect2(-EDGE, CORNER, 0, -CORNER), Vector4(1, 0, 1, 1))
	_add_edge(DisplayServer.WINDOW_EDGE_TOP_LEFT, CURSOR_FDIAGSIZE, Rect2(0, 0, CORNER, CORNER), Vector4(0, 0, 0, 0))
	_add_edge(DisplayServer.WINDOW_EDGE_TOP_RIGHT, CURSOR_BDIAGSIZE, Rect2(-CORNER, 0, 0, CORNER), Vector4(1, 0, 1, 0))
	_add_edge(DisplayServer.WINDOW_EDGE_BOTTOM_LEFT, CURSOR_BDIAGSIZE, Rect2(0, -CORNER, CORNER, 0), Vector4(0, 1, 0, 1))
	_add_edge(DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT, CURSOR_FDIAGSIZE, Rect2(-CORNER, -CORNER, 0, 0), Vector4(1, 1, 1, 1))


func _apply_app_icon() -> void:
	var texture := load(APP_ICON) as Texture2D
	if texture == null:
		return
	var image := texture.get_image()
	if image != null and not image.is_empty():
		DisplayServer.set_icon(image)


func _toggle_maximize() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func _on_header_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	if mouse.double_click:
		_toggle_maximize()
	else:
		DisplayServer.window_start_drag()


# offsets: left, top, right, bottom; anchors: left, top, right, bottom.
func _add_edge(edge: DisplayServer.WindowResizeEdge, cursor: CursorShape, offsets: Rect2, anchors: Vector4) -> void:
	var handle := Control.new()
	handle.name = "Resize%d" % edge
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = cursor
	handle.anchor_left = anchors.x
	handle.anchor_top = anchors.y
	handle.anchor_right = anchors.z
	handle.anchor_bottom = anchors.w
	handle.offset_left = offsets.position.x
	handle.offset_top = offsets.position.y
	handle.offset_right = offsets.size.x
	handle.offset_bottom = offsets.size.y
	handle.gui_input.connect(func(event: InputEvent):
		var mouse := event as InputEventMouseButton
		if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed and \
				DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_start_resize(edge)
	)
	add_child(handle)
