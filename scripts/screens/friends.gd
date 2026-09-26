extends VBoxContainer

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


func _ready() -> void:
	friend_search.text_submitted.connect(_search.bind())
	friend_search.text_changed.connect(_on_search_text_changed)
	search_button.pressed.connect(_search)

	PardexOnline.social_state_changed.connect(_on_social_state_changed)
	PardexOnline.user_search_results.connect(_on_user_search_results)
	PardexOnline.social_notice.connect(_on_social_notice)
	PardexOnline.connection_state_changed.connect(_on_connection_state_changed)

	_social_state = PardexOnline.social_state.duplicate(true)
	_update_connection_state(PardexOnline.connection_state)
	_render_social_state()
	_render_search_results()

	if PardexOnline.is_online():
		PardexOnline.request_social_state()


func _on_connection_state_changed(state: String) -> void:
	_update_connection_state(state)
	if state == "online":
		PardexOnline.request_social_state()


func _update_connection_state(state: String) -> void:
	var online := state == "online"
	friend_search.editable = online
	search_button.disabled = not online

	match state:
		"online":
			var short_id := PardexOnline.account_id.right(8).to_upper()
			connection_hint.text = "● PARDEX Online bağlı  •  Kimlik #%s" % (short_id if not short_id.is_empty() else "HAZIRLANIYOR")
			connection_hint.add_theme_color_override("font_color", Color(0.38, 0.9, 0.64, 1))
		"connecting":
			connection_hint.text = "PARDEX Online bağlantısı kuruluyor..."
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


func _on_user_search_results(results: Array) -> void:
	_search_results = results.duplicate(true)
	_render_search_results()
	if _search_results.is_empty() and not _last_search.is_empty():
		connection_hint.text = "'%s' için kullanıcı bulunamadı." % _last_search
	elif not _last_search.is_empty():
		connection_hint.text = "%d kullanıcı bulundu." % _search_results.size()


func _on_social_notice(message: String) -> void:
	if message.is_empty():
		return
	connection_hint.text = message


func _render_social_state() -> void:
	var incoming: Array = _array_from_state("incoming_requests")
	var friends: Array = _array_from_state("friends")

	requests_panel.visible = not incoming.is_empty()
	_clear_children(requests_list)
	for profile_variant in incoming:
		if typeof(profile_variant) != TYPE_DICTIONARY:
			continue
		var profile: Dictionary = profile_variant
		requests_list.add_child(_make_profile_row(profile, "incoming"))

	_clear_children(friends_list)
	friends_header.text = "ARKADAŞLAR  •  %d" % friends.size()
	if friends.is_empty():
		friends_list.add_child(_make_empty_label("Henüz arkadaşın yok. Yukarıdan kullanıcı ara ve arkadaşlık isteği gönder."))
	else:
		for profile_variant in friends:
			if typeof(profile_variant) != TYPE_DICTIONARY:
				continue
			var profile: Dictionary = profile_variant
			friends_list.add_child(_make_profile_row(profile, "friend"))


func _render_search_results() -> void:
	results_panel.visible = not _last_search.is_empty()
	_clear_children(results_list)
	if _last_search.is_empty():
		return
	if _search_results.is_empty():
		results_list.add_child(_make_empty_label("Aramana uyan PARDEX kullanıcısı bulunamadı."))
		return

	for profile_variant in _search_results:
		if typeof(profile_variant) != TYPE_DICTIONARY:
			continue
		var profile: Dictionary = profile_variant
		results_list.add_child(_make_profile_row(profile, "search"))


func _array_from_state(key: String) -> Array:
	var value = _social_state.get(key, [])
	return value as Array if typeof(value) == TYPE_ARRAY else []


func _make_profile_row(profile: Dictionary, mode: String) -> Control:
	var account_id := str(profile.get("account_id", ""))
	var display_name := str(profile.get("display_name", "Pardus"))
	var tag := str(profile.get("tag", account_id.right(6).to_upper()))
	var online := bool(profile.get("online", false))
	var relationship := str(profile.get("relationship", "none"))

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
	avatar.add_theme_stylebox_override("normal", _avatar_style(online))
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
	meta_label.text = "%s  •  #%s" % [("Çevrimiçi" if online else "Çevrimdışı"), tag]
	meta_label.add_theme_font_size_override("font_size", 12)
	meta_label.add_theme_color_override("font_color", Color(0.38, 0.86, 0.64, 1) if online else Color(0.48, 0.54, 0.63, 1))
	info.add_child(meta_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)

	if mode == "incoming":
		actions.add_child(_make_action_button("KABUL ET", func(): PardexOnline.accept_friend_request(account_id), true))
		actions.add_child(_make_action_button("REDDET", func(): PardexOnline.decline_friend_request(account_id), false, true))
	elif mode == "friend":
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


func _make_action_button(
	text_value: String,
	action: Callable,
	primary := false,
	danger := false,
	disabled := false
) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(104, 34)
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
	style.border_color = Color(0.07, 0.18, 0.26, 1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 12.0
	style.content_margin_top = 10.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 10.0
	return style


func _avatar_style(online: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.16, 0.20, 1) if online else Color(0.055, 0.075, 0.10, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.18, 0.68, 0.70, 1) if online else Color(0.12, 0.17, 0.22, 1)
	style.corner_radius_top_left = 21
	style.corner_radius_top_right = 21
	style.corner_radius_bottom_right = 21
	style.corner_radius_bottom_left = 21
	return style


func _button_style(primary: bool, danger: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if danger:
		style.bg_color = Color(0.34, 0.08, 0.10, 1) if not hovered else Color(0.48, 0.10, 0.13, 1)
	elif primary:
		style.bg_color = Color(0.05, 0.40, 0.56, 1) if not hovered else Color(0.07, 0.54, 0.72, 1)
	else:
		style.bg_color = Color(0.06, 0.10, 0.15, 1) if not hovered else Color(0.08, 0.15, 0.21, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.10, 0.30, 0.38, 1) if not danger else Color(0.55, 0.16, 0.18, 1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	return style


func _button_disabled_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.06, 0.08, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.09, 0.12, 0.16, 1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	return style
