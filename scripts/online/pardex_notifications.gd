extends Node

const PardexIcons := preload("res://scripts/ui/pardex_icons.gd")

const MAX_NOTIFICATIONS := 20

var _main_scene: Control
var _friends_button: Button
var _rooms_button: Button
var _header_row: HBoxContainer
var _friends_badge: PanelContainer
var _rooms_badge: PanelContainer
var _notification_button: Button
var _notification_button_badge: PanelContainer
var _notification_panel: PanelContainer
var _notification_list: VBoxContainer
var _notifications: Array[Dictionary] = []
var _known_friend_requests: Dictionary = {}
var _ui_ready := false
var _bind_retry_scheduled := false


func _ready() -> void:
	PardexOnline.social_state_changed.connect(_on_social_state_changed)
	PardexOnline.room_invite_received.connect(_on_room_invite_received)
	PardexOnline.room_invite_closed.connect(_on_room_invite_closed)
	PardexOnline.connection_state_changed.connect(_on_connection_state_changed)
	call_deferred("_bind_ui")


func _bind_ui() -> void:
	_bind_retry_scheduled = false
	if _ui_ready:
		return

	var scene := get_tree().current_scene
	if scene == null or not (scene is Control):
		_schedule_bind_retry()
		return

	var friends = scene.find_child("FriendsButton", true, false)
	var rooms = scene.find_child("RoomsButton", true, false)
	var header = scene.find_child("HeaderRow", true, false)
	# The rooms badge is optional: the shell may reach rooms through Friends.
	if not (friends is Button) or not (header is HBoxContainer):
		_schedule_bind_retry()
		return

	_main_scene = scene as Control
	_friends_button = friends as Button
	_rooms_button = rooms as Button if rooms is Button else null
	_header_row = header as HBoxContainer
	if not _bind_scene_widgets(_main_scene):
		push_error("PARDEX notifications: missing scene nodes")
		return
	_ui_ready = true

	_on_social_state_changed(PardexOnline.social_state)
	if not PardexOnline.pending_room_invite.is_empty():
		_on_room_invite_received(PardexOnline.pending_room_invite)
	_update_all_badges()
	_render_notifications()


func _schedule_bind_retry() -> void:
	if _bind_retry_scheduled:
		return
	_bind_retry_scheduled = true
	get_tree().create_timer(0.15).timeout.connect(_bind_ui)


# The notification button, badges and panel live in scenes/main.tscn.
# Only live counts and rows are updated here; editor-owned layout is never rebuilt.
func _bind_scene_widgets(scene: Control) -> bool:
	_friends_badge = scene.find_child("FriendsNotificationBadge", true, false) as PanelContainer
	_notification_button = scene.find_child("NotificationButton", true, false) as Button
	_notification_button_badge = scene.find_child("NotificationBadge", true, false) as PanelContainer
	_notification_panel = scene.find_child("NotificationCenter", true, false) as PanelContainer
	_notification_list = scene.find_child("NotificationList", true, false) as VBoxContainer
	var clear_button := scene.find_child("ClearReadButton", true, false) as Button
	if _friends_badge == null or _notification_button == null or _notification_button_badge == null or _notification_panel == null or _notification_list == null or clear_button == null:
		return false
	if not _notification_button.pressed.is_connected(_toggle_notification_panel):
		_notification_button.pressed.connect(_toggle_notification_panel)
	if not clear_button.pressed.is_connected(_clear_read_notifications):
		clear_button.pressed.connect(_clear_read_notifications)
	return true


func _toggle_notification_panel() -> void:
	if _notification_panel == null:
		return
	_notification_panel.visible = not _notification_panel.visible
	if _notification_panel.visible:
		_mark_all_read()
		_render_notifications()


func _on_connection_state_changed(state: String) -> void:
	if state == "offline" and _notification_panel != null:
		_notification_panel.hide()


func _on_social_state_changed(state: Dictionary) -> void:
	var incoming_value = state.get("incoming_requests", [])
	var incoming: Array = incoming_value as Array if typeof(incoming_value) == TYPE_ARRAY else []
	var current_ids: Dictionary = {}

	for profile_variant in incoming:
		if typeof(profile_variant) != TYPE_DICTIONARY:
			continue
		var profile := profile_variant as Dictionary
		var account_id := str(profile.get("account_id", ""))
		if account_id.is_empty():
			continue
		current_ids[account_id] = true
		if not _known_friend_requests.has(account_id):
			var display_name := str(profile.get("display_name", "Bir kullanıcı"))
			_add_notification(
				"friend:%s" % account_id,
				"friend_request",
				"Arkadaşlık isteği",
				"%s sana arkadaşlık isteği gönderdi." % display_name,
				{"account_id": account_id}
			)

	for previous_id in _known_friend_requests.keys():
		if not current_ids.has(previous_id):
			_mark_notification_resolved("friend:%s" % str(previous_id), "İstek işlendi.")

	_known_friend_requests = current_ids
	_set_badge_count(_friends_badge, incoming.size())
	_update_all_badges()
	_render_notifications()


func _on_room_invite_received(invite: Dictionary) -> void:
	var invite_id := str(invite.get("id", ""))
	if invite_id.is_empty():
		return
	var inviter_name := str(invite.get("from_display_name", "Bir arkadaşın"))
	var game_name := str(invite.get("game_name", "PARDEX Oyunu"))
	var room_code := str(invite.get("room_code", ""))
	_add_notification(
		"invite:%s" % invite_id,
		"room_invite",
		"Oda daveti",
		"%s seni %s odasına davet etti. Oda: %s" % [inviter_name, game_name, room_code],
		{"invite_id": invite_id}
	)
	_set_badge_count(_rooms_badge, 1)
	_update_all_badges()
	_render_notifications()


func _on_room_invite_closed(invite_id: String, reason: String) -> void:
	var suffix := _invite_close_text(reason)
	_mark_notification_resolved("invite:%s" % invite_id, suffix)
	_set_badge_count(_rooms_badge, 0 if PardexOnline.pending_room_invite.is_empty() else 1)
	_update_all_badges()
	_render_notifications()


func _add_notification(id: String, kind: String, title: String, body: String, data: Dictionary) -> void:
	var existing_index := _find_notification_index(id)
	if existing_index >= 0:
		var existing := _notifications[existing_index]
		existing["title"] = title
		existing["body"] = body
		existing["data"] = data.duplicate(true)
		existing["resolved"] = false
		existing["read"] = false
		_notifications[existing_index] = existing
	else:
		_notifications.push_front({
			"id": id,
			"kind": kind,
			"title": title,
			"body": body,
			"data": data.duplicate(true),
			"resolved": false,
			"read": false,
		})
		while _notifications.size() > MAX_NOTIFICATIONS:
			_notifications.pop_back()
	_update_all_badges()


func _mark_notification_resolved(id: String, suffix: String) -> void:
	var index := _find_notification_index(id)
	if index < 0:
		return
	var item := _notifications[index]
	item["resolved"] = true
	if not suffix.is_empty():
		item["body"] = "%s  •  %s" % [str(item.get("body", "")), suffix]
	_notifications[index] = item


func _find_notification_index(id: String) -> int:
	for index in range(_notifications.size()):
		if str(_notifications[index].get("id", "")) == id:
			return index
	return -1


func _mark_all_read() -> void:
	for index in range(_notifications.size()):
		var item := _notifications[index]
		item["read"] = true
		_notifications[index] = item
	_update_all_badges()


func _clear_read_notifications() -> void:
	var retained: Array[Dictionary] = []
	for item in _notifications:
		if not bool(item.get("read", false)) or not bool(item.get("resolved", false)):
			retained.append(item)
	_notifications = retained
	_update_all_badges()
	_render_notifications()


func _render_notifications() -> void:
	if not _ui_ready or _notification_list == null:
		return
	for child in _notification_list.get_children():
		child.queue_free()

	if _notifications.is_empty():
		var empty := Label.new()
		empty.custom_minimum_size = Vector2(0, 80)
		empty.text = "Yeni bildirimin yok."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.45, 0.55, 0.65, 1.0))
		_notification_list.add_child(empty)
		return

	for item in _notifications:
		_notification_list.add_child(_make_notification_row(item))


func _make_notification_row(item: Dictionary) -> Control:
	var resolved := bool(item.get("resolved", false))
	var read := bool(item.get("read", false))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _notification_row_style(resolved, read))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var title := Label.new()
	title.text = str(item.get("title", "Bildirim"))
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.86, 0.93, 1.0, 1.0) if not resolved else Color(0.54, 0.62, 0.7, 1.0))
	root.add_child(title)

	var body := Label.new()
	body.text = str(item.get("body", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 12)
	body.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 1.0) if not resolved else Color(0.42, 0.49, 0.56, 1.0))
	root.add_child(body)

	if not resolved:
		var actions := _make_notification_actions(item)
		if actions.get_child_count() > 0:
			root.add_child(actions)
	return panel


func _make_notification_actions(item: Dictionary) -> HBoxContainer:
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	var kind := str(item.get("kind", ""))
	var data_value = item.get("data", {})
	var data: Dictionary = data_value as Dictionary if typeof(data_value) == TYPE_DICTIONARY else {}

	if kind == "friend_request":
		var account_id := str(data.get("account_id", ""))
		if not account_id.is_empty():
			actions.add_child(_action_button("KABUL ET", func(): PardexOnline.accept_friend_request(account_id), true))
			actions.add_child(_action_button("REDDET", func(): PardexOnline.decline_friend_request(account_id), false))
	elif kind == "room_invite":
		var invite_id := str(data.get("invite_id", ""))
		if not invite_id.is_empty():
			actions.add_child(_action_button("KATIL", func(): PardexOnline.accept_room_invite(invite_id), true))
			actions.add_child(_action_button("REDDET", func(): PardexOnline.decline_room_invite(invite_id), false))
	return actions


func _action_button(text_value: String, action: Callable, primary: bool) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(88, 30)
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0, 1.0))
	button.add_theme_stylebox_override("normal", _action_button_style(primary, false))
	button.add_theme_stylebox_override("hover", _action_button_style(primary, true))
	button.pressed.connect(action)
	return button


func _set_badge_count(badge: PanelContainer, count: int) -> void:
	if badge == null:
		return
	var label := badge.get_node_or_null("Count") as Label
	if count <= 0:
		badge.hide()
		return
	badge.show()
	if label != null:
		label.text = "9+" if count > 9 else str(count)


func _update_all_badges() -> void:
	if not _ui_ready:
		return
	var unread := 0
	for item in _notifications:
		if not bool(item.get("read", false)):
			unread += 1
	_set_badge_count(_notification_button_badge, unread)
	if _notification_button != null:
		_notification_button.tooltip_text = "Bildirimler" if unread == 0 else "Bildirimler (%d yeni)" % unread


func _invite_close_text(reason: String) -> String:
	match reason:
		"accepted":
			return "Davet kabul edildi."
		"declined":
			return "Davet reddedildi."
		"expired":
			return "Davet süresi doldu."
		"room_closed":
			return "Oda kapandı."
		"room_full":
			return "Oda doldu."
		"room_in_game":
			return "Oyun başladı."
		_:
			return "Davet kapandı."


func _badge_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.88, 0.18, 0.23, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1.0, 0.45, 0.48, 1.0)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	return style


func _notification_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# Flat header icon, like the window buttons next to it.
	style.bg_color = Color(1, 1, 1, 0.07) if hovered else Color(1, 1, 1, 0.0)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	return style


func _notification_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.025, 0.04, 0.99)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.10, 0.34, 0.46, 1.0)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 4)
	return style


func _notification_row_style(resolved: bool, read: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if resolved:
		style.bg_color = Color(0.025, 0.04, 0.055, 0.86)
	elif read:
		style.bg_color = Color(0.025, 0.065, 0.09, 0.9)
	else:
		style.bg_color = Color(0.035, 0.11, 0.145, 0.96)
	style.border_width_left = 2 if not read and not resolved else 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.12, 0.48, 0.62, 1.0) if not resolved else Color(0.08, 0.14, 0.19, 1.0)
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_right = 9
	style.corner_radius_bottom_left = 9
	return style


func _flat_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.10, 0.14, 0.9) if hovered else Color(0.02, 0.05, 0.075, 0.82)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.08, 0.22, 0.30, 1.0)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	return style


func _action_button_style(primary: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if primary:
		style.bg_color = Color(0.06, 0.46, 0.60, 1.0) if hovered else Color(0.045, 0.34, 0.48, 1.0)
	else:
		style.bg_color = Color(0.20, 0.065, 0.08, 1.0) if hovered else Color(0.13, 0.045, 0.06, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.15, 0.58, 0.72, 1.0) if primary else Color(0.46, 0.13, 0.17, 1.0)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	return style
