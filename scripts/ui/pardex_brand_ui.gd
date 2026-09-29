extends Node

const RETRY_SECONDS := 0.20
const BRAND_SYMBOL := "res://assets/ui/brand_pardex_symbol.png"
const APP_ICON := "res://assets/ui/brand_pardex_app_icon.png"

var _applied := false

func _ready() -> void:
	call_deferred("_apply_brand")

func _apply_brand() -> void:
	if _applied:
		return
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null or scene.name != "Pardex":
		_retry()
		return

	var logo := scene.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox/Brand/Logo") as TextureRect
	var symbol := ResourceLoader.load(BRAND_SYMBOL) as Texture2D
	if logo == null or symbol == null:
		_retry()
		return

	logo.texture = symbol
	logo.custom_minimum_size = Vector2(56, 56)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.modulate = Color(0.96, 1.0, 1.0, 1.0)

	var app_texture := ResourceLoader.load(APP_ICON) as Texture2D
	if app_texture != null:
		var image := app_texture.get_image()
		if image != null and not image.is_empty():
			DisplayServer.set_icon(image)

	_applied = true

func _retry() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(RETRY_SECONDS)
	timer.timeout.connect(_apply_brand)
