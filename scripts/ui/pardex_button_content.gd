extends CenterContainer
# Centered icon + label inside a PARDEX button. Lives in the scene, so the
# disabled look also works for buttons loaded from baked page scenes.

@export var color := Color.WHITE
@export var disabled_color := Color(0.42, 0.48, 0.58)


func _ready() -> void:
	var button := get_parent() as Button
	if button and not button.draw.is_connected(_sync):
		button.draw.connect(_sync)
	_sync()


func _sync() -> void:
	var button := get_parent() as Button
	var tint := disabled_color if button and button.disabled else color
	var icon := get_node_or_null("Group/Icon") as CanvasItem
	if icon:
		icon.modulate = tint
	var text := get_node_or_null("Group/Label") as Label
	if text:
		text.add_theme_color_override("font_color", tint)
