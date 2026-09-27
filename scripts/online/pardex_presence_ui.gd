extends Node

var _profile_state_label: Label
var _bind_retry_scheduled := false


func _ready() -> void:
	PardexOnline.connection_state_changed.connect(_on_connection_state_changed)
	PardexOnline.presence_changed.connect(_on_presence_changed)
	call_deferred("_try_bind_profile_label")


func _exit_tree() -> void:
	_bind_retry_scheduled = false
	_profile_state_label = null


func _try_bind_profile_label() -> void:
	_bind_retry_scheduled = false
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return

	if _is_profile_label_usable():
		_update_profile_state()
		return
	_profile_state_label = null

	var scene := tree.current_scene
	if scene == null or scene.is_queued_for_deletion():
		_schedule_bind_retry()
		return
	var node := scene.find_child("OnlineState", true, false)
	if node is Label and node.is_inside_tree() and not node.is_queued_for_deletion():
		_profile_state_label = node as Label
		_update_profile_state()
	else:
		_schedule_bind_retry()


func _schedule_bind_retry() -> void:
	if _bind_retry_scheduled or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	_bind_retry_scheduled = true
	tree.create_timer(0.15).timeout.connect(_try_bind_profile_label)


func _is_profile_label_usable() -> bool:
	return (
		is_instance_valid(_profile_state_label)
		and _profile_state_label.is_inside_tree()
		and not _profile_state_label.is_queued_for_deletion()
	)


func _on_connection_state_changed(_state: String) -> void:
	if is_inside_tree():
		call_deferred("_try_bind_profile_label")


func _on_presence_changed(_presence: String) -> void:
	if is_inside_tree():
		call_deferred("_try_bind_profile_label")


func _update_profile_state() -> void:
	if not is_inside_tree() or not _is_profile_label_usable():
		return
	if PardexOnline.connection_state == "connecting":
		_profile_state_label.text = "●  Kimlik doğrulanıyor"
		_profile_state_label.add_theme_color_override("font_color", Color(0.94, 0.72, 0.32, 1))
		return
	if not PardexOnline.is_online():
		_profile_state_label.text = "●  Çevrimdışı"
		_profile_state_label.add_theme_color_override("font_color", Color(0.62, 0.67, 0.75, 1))
		return

	var presence := PardexOnline.effective_presence
	match presence:
		"in_game":
			_profile_state_label.text = "●  Oyunda"
			_profile_state_label.add_theme_color_override("font_color", Color(0.38, 0.82, 1.0, 1))
		"busy":
			_profile_state_label.text = "●  Meşgul"
			_profile_state_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42, 1))
		"away":
			_profile_state_label.text = "●  Uzakta"
			_profile_state_label.add_theme_color_override("font_color", Color(0.94, 0.72, 0.32, 1))
		_:
			_profile_state_label.text = "●  Çevrimiçi"
			_profile_state_label.add_theme_color_override("font_color", Color(0.38, 0.86, 0.62, 1))
