@tool
extends Node

# Inspector-only page switcher. It never starts the online client or runs
# the page scripts in the editor; existing scene nodes are the preview.
const PAGE_NAMES := ["StorePage", "LibraryPage", "FriendsPage", "MessagesPage", "ProfilePage", "SettingsPage"]

@export_enum("Mağaza", "Kütüphane", "Arkadaşlar", "Mesajlar", "Profil", "Ayarlar")
var preview_page: int = 0:
	set(value):
		preview_page = clampi(value, 0, PAGE_NAMES.size() - 1)
		if Engine.is_editor_hint():
			call_deferred("_apply_preview")


func _ready() -> void:
	if Engine.is_editor_hint():
		call_deferred("_apply_preview")


func _apply_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	_show_preview_page()


# Kept separate so headless CI can verify the scene layout without booting
# Godot's full editor. Only _apply_preview invokes it during normal usage.
func _show_preview_page() -> void:
	var pages := get_parent().get_node_or_null("Root/Body/ContentColumn/MainMargin/Pages")
	if pages == null:
		return
	for index in PAGE_NAMES.size():
		var page := pages.get_node_or_null(PAGE_NAMES[index]) as Control
		if page != null:
			page.visible = index == preview_page
