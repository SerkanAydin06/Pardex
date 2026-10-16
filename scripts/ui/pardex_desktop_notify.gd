extends Node

# Desktop side of notifications: a system tray icon (where the OS supports
# one) that brings PARDEX back to the front, and a taskbar flash when a
# message or table invite arrives while the window is in the background.

const ICON_PATH := "res://assets/ui/pardex_hub_app_icon.png"
const TRAY_ICON_SIZE := 64

var _indicator := -1
var _restore_mode := Window.MODE_WINDOWED


func _ready() -> void:
	# Remember how the window looked before it was minimized.
	get_window().size_changed.connect(func():
		if get_window().mode != Window.MODE_MINIMIZED:
			_restore_mode = get_window().mode
	)
	_restore_mode = get_window().mode
	if DisplayServer.get_name() == "headless" or not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		return
	var texture := load(ICON_PATH) as Texture2D
	if texture == null:
		return
	var image := texture.get_image()
	image.resize(TRAY_ICON_SIZE, TRAY_ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	_indicator = DisplayServer.create_status_indicator(ImageTexture.create_from_image(image), "PARDEX", _on_tray_pressed)


func _exit_tree() -> void:
	if _indicator >= 0:
		DisplayServer.delete_status_indicator(_indicator)
		_indicator = -1


func is_in_background() -> bool:
	var window := get_window()
	return window.mode == Window.MODE_MINIMIZED or not window.has_focus()


# Flashes the taskbar entry when PARDEX is not the active window.
func notify(text: String) -> void:
	if not is_in_background():
		return
	DisplayServer.window_request_attention()
	if _indicator >= 0:
		DisplayServer.status_indicator_set_tooltip(_indicator, "PARDEX • " + text.left(100))


func set_unread(count: int) -> void:
	if _indicator >= 0:
		DisplayServer.status_indicator_set_tooltip(_indicator, "PARDEX" if count <= 0 else "PARDEX • %d okunmamış mesaj" % count)


func _on_tray_pressed(_button: int, _position: Vector2i) -> void:
	var window := get_window()
	if window.mode == Window.MODE_MINIMIZED:
		window.mode = _restore_mode
	window.grab_focus()
	DisplayServer.window_move_to_foreground()
