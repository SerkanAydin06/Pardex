extends Button

const MAXIMIZE := preload("res://assets/ui/svg/window_maximize.svg")
const RESTORE := preload("res://assets/ui/svg/window_restore.svg")

func _ready() -> void:
	pressed.connect(func(): call_deferred("_refresh_icon"))
	var root_window := get_tree().root
	if root_window != null and not root_window.size_changed.is_connected(_refresh_icon):
		root_window.size_changed.connect(_refresh_icon)
	call_deferred("_refresh_icon")


func _refresh_icon() -> void:
	var mode := DisplayServer.window_get_mode()
	var full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	icon = RESTORE if full or mode == DisplayServer.WINDOW_MODE_MAXIMIZED else MAXIMIZE
	tooltip_text = "Pencereye dön" if full else "Tam ekran"
