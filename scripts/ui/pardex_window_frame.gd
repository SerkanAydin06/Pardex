extends Control

# Borderless desktop window frame, Steam style: the page header drags the
# window, the chrome buttons minimize / toggle full screen / close it and thin invisible
# strips along the edges resize it. Lives in main.tscn above all content.

const APP_ICON := "res://assets/ui/brand_pardex_app_icon.png"
const EDGE := 7.0
const CORNER := 12.0

# Window state to come back to when leaving full screen (the maximize button
# and a header double-click toggle full screen, like a game launcher).
var _restore_mode := DisplayServer.WINDOW_MODE_WINDOWED
var _restore_rect := Rect2i()


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
	(chrome.get_node("MaximizeButton") as Button).pressed.connect(toggle_fullscreen)
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


static func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func toggle_fullscreen() -> void:
	_refresh_button.call_deferred()
	if is_fullscreen():
		_leave_fullscreen()
		return
	var mode := DisplayServer.window_get_mode()
	_restore_mode = DisplayServer.WINDOW_MODE_MAXIMIZED if mode == DisplayServer.WINDOW_MODE_MAXIMIZED else DisplayServer.WINDOW_MODE_WINDOWED
	_restore_rect = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	# Also remembered on disk, so quitting while full screen keeps this window.
	owner.call("_capture_window_state")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _leave_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if _restore_rect.size == Vector2i.ZERO:
		# Started full screen (Ayarlar): fall back to the saved window.
		owner.call("_restore_windowed_state")
		return
	if _restore_mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		# The OS keeps the pre-maximize size for the next "restore down".
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		return
	# Size/position only stick once the windowed mode has been applied.
	await get_tree().process_frame
	DisplayServer.window_set_size(_restore_rect.size)
	DisplayServer.window_set_position(_restore_rect.position)


# Header double-click does not press the button, so update its icon here.
func _refresh_button() -> void:
	var button := (owner as Control).get_node("%WindowChrome").get_node_or_null("MaximizeButton")
	if button != null and button.has_method("_refresh_icon"):
		button.call("_refresh_icon")


func _on_header_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	if mouse.double_click:
		toggle_fullscreen()
	elif not is_fullscreen():
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
