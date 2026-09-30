extends Button

const MAXIMIZE := preload("res://assets/ui/svg/window_maximize.svg")
const RESTORE := preload("res://assets/ui/svg/window_restore.svg")

func _ready() -> void:
	pressed.connect(func(): call_deferred("_refresh_icon"))
	call_deferred("_refresh_icon")


func _refresh_icon() -> void:
	icon = RESTORE if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED else MAXIMIZE
