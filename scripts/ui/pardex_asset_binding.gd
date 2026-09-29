extends Node

# Binds the PNG assets in assets/ui to the redesigned shell without touching
# the page layout code. This runs after main.gd has finished adding its text
# symbols so the real artwork remains authoritative.

const RETRY_SECONDS := 0.15

const NAV_ASSETS := {
	"HomeButton": ["Ana Sayfa", "res://assets/ui/brand_pardex_symbol.png", 21],
	"LibraryButton": ["Kütüphane", "res://assets/ui/icon_library.png", 22],
	"DiscoverButton": ["Keşfet", "res://assets/ui/icon_search.png", 21],
	"FriendsButton": ["Arkadaşlar", "res://assets/ui/icon_friends.png", 22],
}

var _applied := false

func _ready() -> void:
	call_deferred("_bind")

func _bind() -> void:
	if _applied:
		return
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null or scene.name != "Pardex":
		tree.create_timer(RETRY_SECONDS).timeout.connect(_bind)
		return

	for node_name in NAV_ASSETS:
		var button := scene.find_child(node_name, true, false) as Button
		if button == null:
			continue
		var spec: Array = NAV_ASSETS[node_name]
		_apply_button_icon(button, str(spec[0]), str(spec[1]), int(spec[2]))

	var profile_button := scene.find_child("ProfileButton", true, false) as Button
	if profile_button != null:
		# There is no dedicated profile PNG yet; keep the clean circular glyph
		# instead of reusing an unrelated image.
		profile_button.text = "◉     Profil"

	var settings_button := scene.find_child("SettingsButton", true, false) as Button
	if settings_button != null:
		var settings_texture := _texture("res://assets/ui/icon_settings.png")
		if settings_texture != null:
			settings_button.icon = settings_texture
			settings_button.expand_icon = true
			settings_button.add_theme_constant_override("icon_max_width", 18)
			settings_button.text = ""

	_bind_search_icon(scene)
	_apply_window_icon()
	_applied = true

func _apply_button_icon(button: Button, label_text: String, path: String, icon_width: int) -> void:
	var texture := _texture(path)
	if texture == null:
		return
	button.text = label_text
	button.icon = texture
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width", icon_width)
	button.add_theme_constant_override("h_separation", 12)

func _bind_search_icon(scene: Node) -> void:
	var search := scene.find_child("LibrarySearch", true, false) as LineEdit
	if search == null:
		return
	# main.gd adds a temporary unicode magnifier. Hide it once the PNG is bound.
	for child in search.get_children():
		if child is Label and (child as Label).text == "⌕":
			(child as Label).hide()
	var icon := TextureRect.new()
	icon.name = "SearchIconArtwork"
	icon.texture = _texture("res://assets/ui/icon_search.png")
	if icon.texture == null:
		icon.queue_free()
		return
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	icon.offset_left = 10
	icon.offset_top = -10
	icon.offset_right = 30
	icon.offset_bottom = 10
	search.add_child(icon)

func _apply_window_icon() -> void:
	var app_texture := _texture("res://assets/ui/brand_pardex_app_icon.png")
	if app_texture == null:
		return
	var image := app_texture.get_image()
	if image != null and not image.is_empty():
		DisplayServer.set_icon(image)

func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D
