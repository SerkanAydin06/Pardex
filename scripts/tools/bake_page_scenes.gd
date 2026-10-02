extends SceneTree

# One-off generator: builds a page from its script and saves the result as a
# .tscn scene so the layout can be edited in the Godot editor.
#   godot --headless --path . --script res://scripts/tools/bake_page_scenes.gd -- store library
# After a page has its scene, the scene is the source of truth; re-baking
# overwrites manual scene edits.

const PAGES := {
	"store": ["StorePage", "res://scripts/pages/store_page.gd", "res://scenes/pages/store_page.tscn"],
	"library": ["LibraryPage", "res://scripts/pages/library_page.gd", "res://scenes/pages/library_page.tscn"],
	"friends": ["FriendsPage", "res://scripts/pages/social_page.gd", "res://scenes/pages/friends_page.tscn"],
	"profile": ["ProfilePage", "res://scripts/pages/profile_page.gd", "res://scenes/pages/profile_page.tscn"],
	"settings": ["SettingsPage", "", "res://scenes/pages/settings_page.tscn"],
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var names := OS.get_cmdline_user_args()
	if names.is_empty():
		names = PackedStringArray(PAGES.keys())
	for key in names:
		if key == "settings":
			await _bake_settings()
			continue
		var spec: Array = PAGES[key]
		var page := (load(spec[1]) as GDScript).new() as Control
		page.name = spec[0]
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(page)
		await process_frame
		await process_frame
		# Include the rendered rows/cards so the editor shows the page as the
		# app does; the page script re-renders them from live data at runtime.
		page.owner = null
		var UI := load("res://scripts/ui/pardex_ui.gd")
		UI.own(page)
		_tidy_names(page)
		var scene := PackedScene.new()
		var error := scene.pack(page)
		if error == OK:
			error = ResourceSaver.save(scene, spec[2])
		print("bake %s -> %s: %s" % [key, spec[2], error_string(error)])
		page.queue_free()
	quit(0)


# Ayarlar: page title + scroll + the settings screen restyled to the shared
# card/button language, saved as local nodes so every part is editable.
func _bake_settings() -> void:
	var UI := load("res://scripts/ui/pardex_ui.gd")
	var TextFit := load("res://scripts/ui/pardex_text_fit.gd")
	var page := VBoxContainer.new()
	page.name = "SettingsPage"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)
	var heading_row := HBoxContainer.new()
	heading_row.name = "HeadingRow"
	heading_row.add_theme_constant_override("separation", 16)
	var back: Button = UI.button("Geri", "ghost", 14, 40, "arrow_left")
	back.custom_minimum_size.x = 110
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading_row.add_child(UI.named(back, "BackButton"))
	var heading := VBoxContainer.new()
	heading.name = "Heading"
	heading.add_theme_constant_override("separation", 2)
	heading.add_child(UI.label("Ayarlar", 30, UI.TEXT, true))
	heading.add_child(UI.label("PARDEX profilini, hesabını ve bağlantı ayarlarını yönet.", 14, UI.TEXT_2))
	heading_row.add_child(heading)
	page.add_child(heading_row)
	var content := (load("res://scenes/screens/settings.tscn") as PackedScene).instantiate() as Control
	content.scene_file_path = ""
	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	UI.named(content, "SettingsContent")
	var scroll: ScrollContainer = UI.scroll_page(content)
	scroll.name = "Scroll"
	page.add_child(scroll)
	root.add_child(page)
	TextFit.apply(content)
	UI.restyle_screen(content)
	_add_avatar_row(UI, content.get_node("ProfilePanel/VBox"))
	await process_frame
	UI.own(page)
	_tidy_names(page)
	var scene := PackedScene.new()
	var error := scene.pack(page)
	if error == OK:
		error = ResourceSaver.save(scene, "res://scenes/pages/settings_page.tscn")
	print("bake settings -> res://scenes/pages/settings_page.tscn: %s" % error_string(error))
	page.queue_free()


# Auto-generated "@Class@123" names are replaced by readable editor names.
func _tidy_names(node: Node) -> void:
	for child in node.get_children():
		if str(child.name).begins_with("@"):
			var base := child.get_class()
			var index := 1
			while node.has_node(NodePath("%s%d" % [base, index])):
				index += 1
			child.name = "%s%d" % [base, index]
		_tidy_names(child)


# Profil resmi: preview + choose/remove, placed under the name field.
func _add_avatar_row(UI, profile_box: Control) -> void:
	var row := HBoxContainer.new()
	row.name = "AvatarRow"
	row.add_theme_constant_override("separation", 16)
	var preview := CenterContainer.new()
	preview.custom_minimum_size = Vector2(72, 72)
	row.add_child(UI.named(preview, "AvatarPreview"))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.add_theme_constant_override("separation", 2)
	copy.add_child(UI.label("Profil resmi", 15, UI.TEXT, true))
	copy.add_child(UI.label("JPG, PNG ya da WEBP. Ortadan kare kırpılır; arkadaşların da görür.", 13, UI.TEXT_2))
	row.add_child(copy)
	var choose: Button = UI.button("Resim Seç", "primary", 14, 42, "image")
	choose.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(UI.named(choose, "ChooseAvatarButton"))
	var remove: Button = UI.button("Kaldır", "ghost", 14, 42, "trash")
	remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(UI.named(remove, "RemoveAvatarButton"))
	profile_box.add_child(row)
	var name_row := profile_box.get_node_or_null("ProfileRow")
	if name_row != null:
		profile_box.move_child(row, name_row.get_index() + 1)
