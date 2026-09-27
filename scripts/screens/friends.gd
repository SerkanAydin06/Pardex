extends VBoxContainer

@onready var toolbar: HBoxContainer = $Toolbar
@onready var friend_search: LineEdit = $Toolbar/FriendSearch
@onready var search_button: Button = $Toolbar/SearchButton
@onready var connection_hint: Label = $ConnectionHint
@onready var requests_panel: PanelContainer = $ContentScroll/Sections/RequestsPanel
@onready var requests_list: VBoxContainer = $ContentScroll/Sections/RequestsPanel/Requests/RequestsList
@onready var results_panel: PanelContainer = $ContentScroll/Sections/ResultsPanel
@onready var results_list: VBoxContainer = $ContentScroll/Sections/ResultsPanel/Results/ResultsList
@onready var friends_list: VBoxContainer = $ContentScroll/Sections/FriendsPanel/Friends/FriendsList
@onready var friends_header: Label = $ContentScroll/Sections/FriendsPanel/Friends/FriendsHeader

var _social_state: Dictionary = {}
var _search_results: Array = []
var _last_search := ""
var _invite_dialog: ConfirmationDialog
var _active_invite_id := ""
var _presence_select: OptionButton
var _presence_syncing := false


func _ready() -> void:
	_create_presence_selector()
	friend_search.text_submitted.connect(_search.bind())
	friend_search.text_changed.connect(_on_search_text_changed)
	search_button.pressed.connect(_search)

	PardexOnline.social_state_changed.connect(_on_social_state_changed)
	PardexOnline.user_search_results.connect(_on_user_search_results)
	PardexOnline.social_notice.connect(_on_social_notice)
	PardexOnline.connection_state_changed.connect(_on_connection_state_changed)
	PardexOnline.presence_changed.connect(_on_presence_changed)
	PardexOnline.room_state_changed.connect(_on_room_state_changed)
	PardexOnline.room_left.connect(_on_room_left)
	PardexOnline.room_invite_received.connect(_on_room_invite_received)
	PardexOnline.room_invite_closed.connect(_on_room_invite_closed)

	_create_invite_dialog()
	_social_state = PardexOnline.social_state.duplicate(true)
	_sync_presence_selector()
	_update_connection_state(PardexOnline.connection_state)
	_render_social_state()
	_render_search_results()

	if PardexOnline.is_online():
		PardexOnline.request_social_state()


func _create_presence_selector() -> void:
	_presence_select = OptionButton.new()
	_presence_select.name = "PresenceSelect"
	_presence_select.custom_minimum_size = Vector2(152, 42)
	_presence_select.focus_mode = Control.FOCUS_NONE
	_presence_select.add_theme_font_size_override("font_size", 12)
	_presence_select.add_theme_color_override("font_color", Color(0.86, 0.92, 0.98, 1))
	_presence_select.add_theme_stylebox_override("normal", _presence_button_style(false))
	_presence_select.add_theme_stylebox_override("hover", _presence_button_style(true))
	_presence_select.add_item("●  Çevrimiçi", 0)
	_presence_select.set_item_metadata(0, "online")
	_presence_select.add_item("◐  Uzakta", 1)
	_presence_select.set_item_metadata(1, "away")
	_presence_select.add_item("●  Meşgul", 2)
	_presence_select.set_item_metadata(2, "busy")
	_presence_select.item_selected.connect(_on_presence_selected)
	toolbar.add_child(_presence_select)
	toolbar.move_child(_presence_select, 0)


func _on_presence_selected(index: int) -> void:
	if _presence_syncing:
		return
	var metadata = _presence_select.get_item_metadata(index)
	PardexOnline.set_presence_status(str(metadata))
	_update_connection_state(PardexOnline.connection_state)


func _sync_presence_selector() -> void:
	if _presence_select == null:
		return
	_presence_syncing = true
	for index in range(_presence_select.item_count):
		if str(_presence_select.get_item_metadata(index)) == PardexOnline.presence_status:
			_presence_select.select(index)
			break
	_presence_syncing = false


func _create_invite_dialog() -> void:
	_invite_dialog = ConfirmationDialog.new()
	_invite_dialog.title = "PARDEX Oda Daveti"
	_invite_dialog.min_size = Vector2i(500, 250)
	_invite_dialog.exclusive = true
	get_tree().root.add_child.call_deferred(_invite_dialog)
	_invite_dialog.confirmed.connect(_accept_active_invite)
	_invite_dialog.canceled.connect(_decline_active_invite)
	call_deferred("_style_invite_dialog_buttons")


func _style_invite_dialog_buttons() -> void:
	if _invite_dialog == null:
		return
	var ok_button := _invite_dialog.get_ok_button()
	if ok_button != null:
		ok_button.text = "KATIL"
	var cancel_button := _invite_dialog.get_cancel_button()
	if cancel_button != null:
		cancel_button.text = "REDDET"


func _on_connection_state_changed(state: String) -> void:
	_update_connection_state(state)
	if state == "online":
		PardexOnline.request_social_state()
	_render_social_state()


func _on_presence_changed(_presence: String) -> void:
	_sync_presence_selector()
	_update_connection_state(PardexOnline.connection_state)
	_render_social_state()


func _update_connection_state(state: String) -> void:
	var online := state == "online" and PardexOnline.is_identity_ready()
	friend_search.editable = online
	search_button.disabled = not online

	match state:
		"online":
			var short_id := PardexOnline.account_id.right(8).to_upper()
			var presence_label := _presence_label(PardexOnline.effective_presence)
			connection_hint.text = "● PARDEX Online bağlı  •  Kimlik #%s  •  %s" % [short_id, presence_label]
			connection_hint.add_theme_color_override("font_color", _presence_color(PardexOnline.effective_presence))
		"connecting":
			connection_hint.text = "PARDEX kimliği doğrulanıyor..."
			connection_hint.add_theme_color_override("font_color", Color(0.94, 0.72, 0.32, 1))
		_:
			connection_hint.text = "Arkadaş özellikleri için PARDEX Online bağlantısı gerekli."
			connection_hint.add_theme_color_override("font_color", Color(0.62, 0.67, 0.75, 1))


func _on_search_text_changed(value: String) -> void:
	if value.strip_edges().length() >= 2:
		return
	_last_search = ""
	_search_results.clear()
	_render_search_results()


func _search(_submitted_text := "") -> void:
	var query := friend_search.text.strip_edges()
	if query.length() < 2:
		_on_social_notice("Arama için en az 2 karakter yaz.")
		_search_results.clear()
		_render_search_results()
		return
	_last_search = query
	PardexOnline.search_users(query)
	connection_hint.text = "'%s' için PARDEX kullanıcıları aranıyor..." % query


func _on_social_state_changed(state: Dictionary) -> void:
	_social_state = state.duplicate(true)
	_render_social_state()
	if not _last_search.is_empty() and PardexOnline.is_online():
		PardexOnline.search_users(_last_search)


func _on_room_state_changed(_room: Dictionary) -> void:
	_render_social_state()
	_render_search_results()


func _on_room_left() -> void:
	_render_social_state()
	_render_search_results()


func _on_user_search_results(results: Array) -> void:
	_search_results = results.duplicate(true)
	_render_search_results()
	if _search_results.is_empty() and not _last_search.is_empty():
		connection_hint.text = "'%s' için kullanıcı bulunamadı." % _last_search
	elif not _last_search.is_empty():
		connection_hint.text = "%d kullanıcı bulundu." % _search_results.size()


func _on_social_notice(message: String) -> void:
	if not message.is_empty():
		connection_hint.text = message


func _on_room_invite_received(invite: Dictionary) -> void:
	var invite_id := str(invite.get("id", ""))
	if invite_id.is_empty():
		return
	if not _active_invite_id.is_empty() and _active_invite_id != invite_id:
		PardexOnline.decline_room_invite(_active_invite_id)

	_active_invite_id = invite_id
	var inviter_name := str(invite.get("from_display_name", "Bir arkadaşın"))
	var game_name := str(invite.get("game_name", "PARDEX Oyunu"))
	var room_code := str(invite.get("room_code", ""))
	var member_count := int(invite.get("member_count", 0))
	var max_players := int(invite.get("max_players", 0))
	_invite_dialog.dialog_text = "%s seni %s odasına davet ediyor.\n\nOda: %s\nOyuncular: %d / %d\n\nOdaya katılmak ister misin?" % [
		inviter_name,
		game_name,
		room_code,
		member_count,
		max_players,
	]
	_style_invite_dialog_buttons()
	_invite_dialog.popup_centered(Vector2i(520, 260))


func _on_room_invite_closed(invite_id: String, reason: String) -> void:
	if invite_id != _active_invite_id:
		return
	var was_visible := _invite_dialog.visible
	_active_invite_id = ""
	_invite_dialog.hide()
	if was_visible and reason == "expired":
		_on_social_notice("Oda davetinin süresi doldu.")
	elif was_visible and reason in ["room_closed", "room_full", "room_in_game"]:
		_on_social_notice("Davet edilen oda artık katılıma uygun değil.")


func _accept_active_invite() -> void:
	if _active_invite_id.is_empty():
		return
	var invite_id := _active_invite_id
	_invite_dialog.hide()
	connection_hint.text = "Odaya katılınıyor..."
	PardexOnline.accept_room_invite(invite_id)


func _decline_active_invite() -> void:
	if _active_invite_id.is_empty():
		return
	var invite_id := _active_invite_id
	_invite_dialog.hide()
	PardexOnline.decline_room_invite(invite_id)


func _send_room_invite(account_id: String) -> void:
	PardexOnline.send_room_invite(account_id)
	connection_hint.text = "Oda daveti gönderiliyor..."


func _join_friend_room(account_id: String) -> void:
	PardexOnline.join_friend_room(account_id)
	connection_hint.text = "Arkadaşının odasına katılınıyor..."


func _render_social_state() -> void:
	var incoming: Array = _array_from_state("incoming_requests")
	var friends: Array = _array_from_state("friends")

	requests_panel.visible = not incoming.is_empty()
	_clear_children(requests_list)
	for profile_variant in incoming:
		if typeof(profile_variant) == TYPE_DICTIONARY:
			requests_list.add_child(_make_profile_row(profile_variant as Dictionary, "incoming"))

	_clear_children(friends_list)
	friends_header.text = "ARKADAŞLAR  •  %d" % friends.size()
	if friends.is_empty():
		friends_list.add_child(_make_empty_label("Henüz arkadaşın yok. Yukarıdan kullanıcı ara ve arkadaşlık isteği gönder."))
	else:
		for profile_variant in friends:
			if typeof(profile_variant) == TYPE_DICTIONARY:
				friends_list.add_child(_make_profile_row(profile_variant as Dictionary, "friend"))


func _render_search_results() -> void:
	results_panel.visible = not _last_search.is_empty()
	_clear_children(results_list)
	if _last_search.is_empty():
		return
	if _search_results.is_empty():
		results_list.add_child(_make_empty_label("Aramana uyan PARDEX kullanıcısı bulunamadı."))
		return
	for profile_variant in _search_results:
		if typeof(profile_variant) == TYPE_DICTIONARY:
			results_list.add_child(_make_profile_row(profile_variant as Dictionary, "search"))


func _array_from_state(key: String) -> Array:
	var value = _social_state.get(key, [])
	return value as Array if typeof(value) == TYPE_ARRAY else []


func _make_profile_row(profile: Dictionary, mode: String) -> Control:
	var account_id := str(profile.get("account_id", ""))
	var display_name := str(profile.get("display_name", "Pardus"))
	var tag := str(profile.get("tag", account_id.right(6).to_upper()))
	var online := bool(profile.get("online", false))
	var relationship := str(profile.get("relationship", "none"))
	var presence := str(profile.get("presence", "online" if online else "offline"))
	var game_name := str(profile.get("game_name", ""))
	var in_room := bool(profile.get("in_room", false))
	var room_joinable := bool(profile.get("room_joinable", false))
	var member_count := int(profile.get("room_member_count", 0))
	var max_players := int(profile.get("room_max_players", 0))

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _row_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var avatar := Label.new()
	avatar.custom_minimum_size = Vector2(42, 42)
	avatar.text = display_name.left(1).to_upper()
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.add_theme_font_size_override("font_size", 19)
	avatar.add_theme_color_override("font_color", Color(0.80, 0.95, 1.0, 1))
	avatar.add_theme_stylebox_override("normal", _avatar_style(presence))
	row.add_child(avatar)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98, 1))
	info.add_child(name_label)

	var meta_label := Label.new()
	meta_label.text = _profile_meta_text(presence, game_name, in_room, member_count, max_players, tag)
	meta_label.add_theme_font_size_override("font_size", 12)
	meta_label.add_theme_color_override("font_color", _presence_color(presence))
	info.add_child(meta_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)

	if mode == "incoming":
		actions.add_child(_make_action_button("KABUL ET", func(): PardexOnline.accept_friend_request(account_id), true))
		actions.add_child(_make_action_button("REDDET", func(): PardexOnline.decline_friend_request(account_id), false, true))
	elif mode == "friend":
		if _friend_is_in_current_room(account_id):
			actions.add_child(_make_action_button("AYNI ODA", Callable(), false, false, true))
		elif room_joinable:
			actions.add_child(_make_action_button("ODAYA KATIL", func(): _join_friend_room(account_id), true))
		elif presence == "in_game":
			actions.add_child(_make_action_button("OYUNDA", Callable(), false, false, true))
		elif presence == "offline":
			actions.add_child(_make_action_button("ÇEVRİMDIŞI", Callable(), false, false, true))
		elif not PardexOnline.current_room.is_empty() and not bool(PardexOnline.current_room.get("launching", false)):
			actions.add_child(_make_action_button("DAVET ET", func(): _send_room_invite(account_id), true))
		elif in_room:
			actions.add_child(_make_action_button("ODA DOLU", Callable(), false, false, true))
		else:
			actions.add_child(_make_action_button("ODA YOK", Callable(), false, false, true))
		actions.add_child(_make_action_button("KALDIR", func(): PardexOnline.remove_friend(account_id), false, true))
	else:
		match relationship:
			"friend":
				actions.add_child(_make_action_button("ARKADAŞ", Callable(), false, false, true))
			"incoming":
				actions.add_child(_make_action_button("KABUL ET", func(): PardexOnline.accept_friend_request(account_id), true))
			"outgoing":
				actions.add_child(_make_action_button("İSTEK GİTTİ", Callable(), false, false, true))
				actions.add_child(_make_action_button("İPTAL", func(): PardexOnline.cancel_friend_request(account_id), false, true))
			_:
				actions.add_child(_make_action_button("ARKADAŞ EKLE", func(): PardexOnline.send_friend_request(account_id), true))

	return panel


func _friend_is_in_current_room(account_id: String) -> bool:
	if PardexOnline.current_room.is_empty():
		return false
	var members = PardexOnline.current_room.get("members", [])
	if typeof(members) != TYPE_ARRAY:
		return false
	for member_variant in members as Array:
		if typeof(member_variant) == TYPE_DICTIONARY and str((member_variant as Dictionary).get("account_id", "")) == account_id:
			return true
	return false


func _profile_meta_text(presence: String, game_name: String, in_room: bool, member_count: int, max_players: int, tag: String) -> String:
	var parts: Array[String] = [_presence_label(presence)]
	if not game_name.is_empty():
		parts.append(game_name + (" oynuyor" if presence == "in_game" else " odasında"))
	if in_room and max_players > 0 and presence != "in_game":
		parts.append("%d/%d" % [member_count, max_players])
	parts.append("#%s" % tag)
	return "  •  ".join(parts)


func _presence_label(presence: String) -> String:
	match presence:
		"in_game": return "Oyunda"
		"busy": return "Meşgul"
		"away": return "Uzakta"
		"online": return "Çevrimiçi"
		_: return "Çevrimdışı"


func _presence_color(presence: String) -> Color:
	match presence:
		"in_game": return Color(0.38, 0.82, 1.0, 1)
		"busy": return Color(1.0, 0.48, 0.42, 1)
		"away": return Color(0.94, 0.72, 0.32, 1)
		"online": return Color(0.38, 0.86, 0.64, 1)
		_: return Color(0.48, 0.54, 0.63, 1)


func _make_action_button(text_value: String, action: Callable, primary := false, danger := false, disabled := false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(108, 34)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = disabled
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color(0.88, 0.93, 0.98, 1))
	button.add_theme_color_override("font_disabled_color", Color(0.48, 0.54, 0.62, 1))
	button.add_theme_stylebox_override("normal", _button_style(primary, danger, false))
	button.add_theme_stylebox_override("hover", _button_style(primary, danger, true))
	button.add_theme_stylebox_override("disabled", _button_disabled_style())
	if not disabled and action.is_valid():
		button.pressed.connect(action)
	return button


func _make_empty_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.48, 0.55, 0.64, 1))
	label.custom_minimum_size = Vector2(0, 44)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.037, 0.058, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.08, 0.18, 0.26, 0.9)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _avatar_style(presence: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.09, 0.13, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = _presence_color(presence)
	style.corner_radius_top_left = 21
	style.corner_radius_top_right = 21
	style.corner_radius_bottom_left = 21
	style.corner_radius_bottom_right = 21
	return style


func _button_style(primary: bool, danger: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if danger:
		style.bg_color = Color(0.22, 0.045, 0.055, 0.96) if hovered else Color(0.13, 0.03, 0.04, 0.88)
		style.border_color = Color(0.88, 0.24, 0.28, 0.95)
	elif primary:
		style.bg_color = Color(0.035, 0.20, 0.26, 0.98) if hovered else Color(0.025, 0.13, 0.18, 0.95)
		style.border_color = Color(0.18, 0.68, 0.88, 0.95)
	else:
		style.bg_color = Color(0.035, 0.055, 0.078, 0.95)
		style.border_color = Color(0.12, 0.20, 0.28, 0.9)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _button_disabled_style() -> StyleBoxFlat:
	var style := _button_style(false, false, false)
	style.bg_color = Color(0.025, 0.035, 0.05, 0.7)
	style.border_color = Color(0.07, 0.10, 0.14, 0.8)
	return style


func _presence_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.10, 0.14, 0.98) if hovered else Color(0.018, 0.055, 0.08, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.14, 0.45, 0.58, 0.95)
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style
