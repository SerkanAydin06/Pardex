extends PanelContainer

# Keeps the desktop shell on real SVG assets even when legacy helpers assign
# generated icon textures during _ready(). Attached to BrandHeader so it is
# part of the scene and runs after the main shell has finished building.

const BRAND := preload("res://assets/ui/svg/brand_pardex_symbol.svg")
const STORE := preload("res://assets/ui/svg/icon_store.svg")
const LIBRARY := preload("res://assets/ui/svg/icon_library.svg")
const FRIENDS := preload("res://assets/ui/svg/icon_friends.svg")
const PROFILE := preload("res://assets/ui/svg/icon_profile.svg")
const SETTINGS := preload("res://assets/ui/svg/icon_settings.svg")
const SEARCH := preload("res://assets/ui/svg/icon_search.svg")
const BELL := preload("res://assets/ui/svg/icon_bell.svg")

const WINDOW_NARROW := 1280.0

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_apply_shell_assets")


func _apply_shell_assets() -> void:
	var main := get_tree().current_scene as Control
	if main == null:
		return
	_apply_navigation(main)
	_apply_search(main)
	_apply_notification(main.find_child("NotificationButton", true, false))
	_apply_brand(main)
	_keep_header_actions_visible(main)
	if not main.resized.is_connected(_on_main_resized):
		main.resized.connect(_on_main_resized)
	_on_main_resized()


func _apply_navigation(main: Control) -> void:
	var icons := {
		"StoreButton": STORE,
		"LibraryButton": LIBRARY,
		"FriendsButton": FRIENDS,
		"ProfileButton": PROFILE,
		"SettingsButton": SETTINGS,
	}
	for node_name in icons:
		var button := main.find_child(node_name, true, false) as Button
		if button == null:
			continue
		button.icon = icons[node_name]
		button.expand_icon = false


func _apply_search(main: Control) -> void:
	var field := main.find_child("LibrarySearch", true, false) as LineEdit
	if field == null:
		return
	for child in field.get_children():
		if child is TextureRect:
			(child as TextureRect).texture = SEARCH
			return


func _apply_notification(node: Node) -> void:
	var button := node as Button
	if button == null or button.name != "NotificationButton":
		return
	button.icon = BELL
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", 20)


func _apply_brand(main: Control) -> void:
	var title := main.find_child("BrandTitle", true, false) as Label
	if title != null:
		title.add_theme_font_size_override("font_size", 31)
		title.add_theme_color_override("font_color", Color("3bc8ff"))
	var logo := main.find_child("Logo", true, false) as TextureRect
	if logo != null:
		logo.texture = BRAND
		logo.custom_minimum_size = Vector2(58, 58)


func _keep_header_actions_visible(main: Control) -> void:
	var chrome := main.find_child("WindowChrome", true, false)
	if chrome == null:
		return
	var secondary := chrome.get_node_or_null("SecondaryAction") as Button
	if secondary != null:
		secondary.visible = true
	var separator := chrome.get_node_or_null("Separator") as Control
	if separator != null:
		separator.visible = true


func _on_main_resized() -> void:
	var main := get_tree().current_scene as Control
	if main == null:
		return
	# Match the brand header to the responsive sidebar width used by main.gd.
	var target_width := 214.0 if main.size.x <= WINDOW_NARROW else 258.0
	custom_minimum_size = Vector2(target_width, custom_minimum_size.y)
	# main.gd applies its responsive rules in the same resize cycle; reassert the
	# reference header actions afterwards so the reward button is not hidden.
	call_deferred("_keep_header_actions_visible_by_id", main.get_instance_id())


func _keep_header_actions_visible_by_id(instance_id: int) -> void:
	var instance := instance_from_id(instance_id)
	if instance is Control:
		_keep_header_actions_visible(instance as Control)


func _on_node_added(node: Node) -> void:
	if node.name == "NotificationButton":
		call_deferred("_apply_notification_by_id", node.get_instance_id())


func _apply_notification_by_id(instance_id: int) -> void:
	var instance := instance_from_id(instance_id)
	if instance is Node:
		_apply_notification(instance as Node)
