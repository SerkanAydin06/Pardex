extends Node

# Keeps existing screen roots and node paths intact while placing long screens
# inside ScrollContainers. This lets main.gd continue addressing children by
# their current relative paths.

const RETRY_SECONDS := 0.20

var _bound := false
var _main: Control
var _rooms_root: VBoxContainer
var _settings_root: VBoxContainer
var _rooms_wrapper: ScrollContainer
var _settings_wrapper: ScrollContainer


func _ready() -> void:
	call_deferred("_bind")


func _bind() -> void:
	if _bound:
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		_retry()
		return
	var scene := tree.current_scene
	if scene.name != "Pardex":
		_retry()
		return

	_main = scene as Control
	# Secondary screens are instantiated dynamically by main.gd.
	_rooms_root = _find_child_vbox("RoomsContent")
	_settings_root = _find_child_vbox("SettingsContent")
	if _rooms_root == null or _settings_root == null:
		_retry()
		return

	_rooms_wrapper = _wrap_root(_rooms_root, "RoomsScroll")
	_settings_wrapper = _wrap_root(_settings_root, "SettingsScroll")
	_bound = _rooms_wrapper != null and _settings_wrapper != null
	if not _bound:
		_retry()
		return

	_sync_wrapper_visibility(_rooms_root, _rooms_wrapper)
	_sync_wrapper_visibility(_settings_root, _settings_wrapper)
	_rooms_root.visibility_changed.connect(_sync_wrapper_visibility.bind(_rooms_root, _rooms_wrapper))
	_settings_root.visibility_changed.connect(_sync_wrapper_visibility.bind(_settings_root, _settings_wrapper))
	get_window().size_changed.connect(_on_window_size_changed)
	_apply_density()


func _retry() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(RETRY_SECONDS).timeout.connect(_bind)


func _find_child_vbox(node_name: String) -> VBoxContainer:
	var main_vbox := _main.get_node_or_null("MainMargin/MainVBox")
	if main_vbox == null:
		return null
	for child in main_vbox.get_children():
		if child.name == node_name and child is VBoxContainer:
			return child as VBoxContainer
	return null


func _wrap_root(root: VBoxContainer, wrapper_name: String) -> ScrollContainer:
	var parent := root.get_parent()
	if parent == null:
		return null
	var old_index := root.get_index()
	var wrapper := ScrollContainer.new()
	wrapper.name = wrapper_name
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrapper.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(wrapper)
	parent.move_child(wrapper, old_index)
	root.reparent(wrapper, false)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return wrapper


func _sync_wrapper_visibility(root: Control, wrapper: Control) -> void:
	if root == null or wrapper == null:
		return
	wrapper.visible = root.visible


func _on_window_size_changed() -> void:
	call_deferred("_apply_density")


func _apply_density() -> void:
	if not _bound:
		return
	var width := DisplayServer.window_get_size().x
	var compact := width <= 1400
	var narrow := width <= 1180

	_rooms_root.add_theme_constant_override("separation", 9 if narrow else (10 if compact else 12))
	_settings_root.add_theme_constant_override("separation", 9 if narrow else (10 if compact else 12))

	# Preserve readable controls instead of scaling text. Only reduce oversized
	# decorative intro blocks on smaller laptop windows.
	var rooms_intro := _rooms_root.get_node_or_null("Intro") as Control
	if rooms_intro != null:
		rooms_intro.custom_minimum_size = Vector2(0, 98 if narrow else (108 if compact else 122))

	var profile_panel := _settings_root.get_node_or_null("ProfilePanel") as Control
	if profile_panel != null:
		profile_panel.custom_minimum_size = Vector2(0, 0)
