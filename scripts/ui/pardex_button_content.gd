extends CenterContainer
# Centered icon + label inside a PARDEX button. Lives in the scene, so the
# disabled look also works for buttons loaded from baked page scenes.

@export var sync_native := false
@export var color := Color.WHITE
@export var disabled_color := Color(0.42, 0.48, 0.58)


func _ready() -> void:
	var button := get_parent() as Button
	if button and not button.draw.is_connected(_sync):
		button.draw.connect(_sync)
	_sync()


func _sync() -> void:
	var button := get_parent() as Button
	var tint := color
	if button:
		var color_name := "font_disabled_color" if button.disabled else "font_color"
		tint = button.get_theme_color(color_name)
		if sync_native:
			tint = preload("res://themes/pardex_theme.tres").get_color(color_name, button.theme_type_variation)
	var icon := get_node_or_null("Group/Icon") as CanvasItem
	if icon:
		icon.modulate = tint
		if sync_native and button:
			(icon as TextureRect).texture = button.icon
	var text := get_node_or_null("Group/Label") as Label
	if text:
		if sync_native and button:
			text.text = button.text
		text.add_theme_color_override("font_color", tint)
