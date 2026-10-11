extends VBoxContainer

# Arkadaşlar: hero, online friends, friends in game, conversation panel,
# pending requests and suggestions.
#
# PARDEX has no rooms: "Oyna" opens the game's menu and tables are hosted and
# joined by code inside the game. A friend at an open table shows "Katıl".
# Messaging, voice and friend suggestions have no server support yet and say so.

signal toast(message: String)
# Opens the Mesajlar tab on this friend's conversation ("" = most recent).
signal message_requested(account_id: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")
const HERO_HEIGHT := 300.0

const ROW_ACTION_WIDTH := 104.0

var _show_all := false
# Top bar search (main.gd): filters friends and searches PARDEX users.
var _query := ""
var _user_results: Array = []
var _search_timer: Timer
var _columns: HBoxContainer
var _left: VBoxContainer
var _online_title: Label
var _online_list: VBoxContainer
var _playing_title: Label
var _playing_row: HBoxContainer
var _right: VBoxContainer
var _requests_title: Label
var _requests_list: VBoxContainer
var _hero_bullets: Control
var _friend_menu: PopupMenu
var _menu_account_id := ""
var _add_dialog: AcceptDialog
var _add_results: VBoxContainer
var _add_hint: Label
var _last_search := ""
var _invite_dialog: ConfirmationDialog
var _active_invite_id := ""


func _ready() -> void:
	# The layout lives in scenes/pages/friends_page.tscn; building from code
	# only happens when the script runs without its scene.
	if get_child_count() == 0:
		_build()
		UI.own(self)
	_bind()
	_bind_friend_menu()
	_bind_add_dialog()
	_bind_invite_dialog()
	PardexOnline.social_state_changed.connect(func(_state):
		# Refresh search results too, so "Ekle" turns into "İsteği İptal Et".
		if _query.length() >= 2:
			_search_timer.start()
		_render()
	)
	PardexOnline.avatar_ready.connect(func(_account_id): _render())
	PardexOnline.connection_state_changed.connect(_on_connection_state_changed)
	PardexOnline.room_state_changed.connect(func(_room_state): _render())
	PardexOnline.room_left.connect(_render)
	PardexOnline.user_search_results.connect(_on_search_results)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.35
	_search_timer.timeout.connect(func():
		if _query.length() >= 2 and PardexOnline.is_online():
			PardexOnline.search_users(_query)
	)
	add_child(_search_timer)
	PardexOnline.social_notice.connect(func(message: String): toast.emit(message))
	PardexOnline.room_invite_received.connect(_on_room_invite_received)
	PardexOnline.room_invite_closed.connect(_on_room_invite_closed)
	if PardexOnline.is_online():
		PardexOnline.request_social_state()
	_render()


func _bind() -> void:
	_columns = %Columns
	_left = %LeftColumn
	_online_title = %OnlineTitle
	_online_list = %OnlineList
	_playing_title = %PlayingTitle
	_playing_row = %PlayingRow
	_right = %RightColumn
	_requests_title = %RequestsTitle
	_requests_list = %RequestsList
	_hero_bullets = %HeroBullets
	(%AddFriendButton as Button).pressed.connect(_open_add_dialog)
	var toggle := %OnlineToggle as Button
	toggle.pressed.connect(func():
		_show_all = not _show_all
		toggle.text = ("Çevrimiçileri Göster" if _show_all else "Tümünü Gör") + "  "
		_render_online()
	)


func _build() -> void:
	add_theme_constant_override("separation", 0)
	var body := UI.vbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UI.scroll_page(body))
	body.add_child(_build_hero())
	var columns := UI.named(UI.hbox(16), "Columns") as HBoxContainer
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.custom_minimum_size.y = 560
	body.add_child(columns)
	columns.add_child(_build_left())
	columns.add_child(_build_right())


func apply_layout(content_width: float) -> void:
	# Chat has its own tab (Mesajlar); the friend list takes the free width.
	_right.visible = true
	_hero_bullets.visible = content_width >= 960.0
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.custom_minimum_size.x = clampf(content_width * 0.3, 320.0, 430.0)


# ------------------------------------------------------------------ data

func _friends() -> Array:
	var value = PardexOnline.social_state.get("friends", [])
	return value if typeof(value) == TYPE_ARRAY else []


func _requests(key: String) -> Array:
	var value = PardexOnline.social_state.get(key, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _presence(profile: Dictionary) -> String:
	return str(profile.get("presence", "online" if bool(profile.get("online", false)) else "offline"))


func _activity(profile: Dictionary) -> String:
	var presence := _presence(profile)
	var game_name := str(profile.get("game_name", ""))
	if not game_name.is_empty() and (presence == "in_game" or bool(profile.get("in_room", false))):
		return game_name
	if presence == "offline":
		return "Çevrimdışı"
	return "Ana Menüde"


func _find_friend(account_id: String) -> Dictionary:
	for profile in _friends():
		if typeof(profile) == TYPE_DICTIONARY and str(profile.get("account_id", "")) == account_id:
			return profile
	return {}


func _room() -> Dictionary:
	return PardexOnline.current_room


func _room_members() -> Array:
	var members = _room().get("members", [])
	return members if typeof(members) == TYPE_ARRAY else []


func _friend_in_my_room(account_id: String) -> bool:
	for member in _room_members():
		if typeof(member) == TYPE_DICTIONARY and str(member.get("account_id", "")) == account_id:
			return true
	return false


# ------------------------------------------------------------------ hero

func _build_hero() -> Control:
	var frame := UI.image(Catalog.texture("res://assets/ui/hero_friends.png"), Vector2(0, HERO_HEIGHT), 16)
	frame.add_theme_stylebox_override("panel", UI.glow_style(0, 16))
	frame.add_child(UI.shade(0.95, true))
	var row := UI.hbox(20)
	frame.add_child(UI.margin(row, 30, 20, 24, 20))
	var text := UI.vbox(10)
	UI.expand(text)
	row.add_child(text)
	var tag := UI.panel(0, UI.box(Color(UI.BG, 0.6), 8, UI.BORDER_HI, 1, 8))
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag.add_child(UI.label("ARKADAŞLAR", 13, UI.ACCENT, true))
	text.add_child(tag)
	text.add_child(UI.label("Arkadaşların", 42, UI.TEXT, true))
	text.add_child(UI.label("Arkadaşlarını bul, mesajlaş ve aynı oyunda buluş.", 16, UI.TEXT_2))
	text.add_child(UI.vspacer())
	var actions := UI.hbox(14)
	text.add_child(actions)
	var add := UI.button("Arkadaş Ekle", "primary", 15, 48, "user_plus")
	add.custom_minimum_size.x = 210
	actions.add_child(UI.named(add, "AddFriendButton"))

	var bullets := UI.feature_card([
		["friends", "Birlikte Oyna", "Arkadaşının açık masasına doğrudan katıl."],
		["message", "Mesajlaşma", "Arkadaşlarınla PARDEX üzerinden doğrudan yazış."],
		["user_plus", "Yeni Arkadaşlar Keşfet", "Üstteki aramayla PARDEX kullanıcılarını bul ve ekle."],
	], 330)
	row.add_child(UI.named(bullets, "HeroBullets"))
	return frame


# ------------------------------------------------------------------ left column

func _build_left() -> Control:
	var left := UI.named(UI.vbox(16), "LeftColumn") as VBoxContainer
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var online := UI.panel(14)
	online.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(10)
	online.add_child(column)
	var header := UI.section_header("Çevrimiçi", "Tümünü Gör", 18, "users_group", UI.GREEN)
	UI.named(header.get_node("Title"), "OnlineTitle")
	UI.named(header.get_node("Link"), "OnlineToggle")
	column.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var online_list := UI.named(UI.vbox(6), "OnlineList") as VBoxContainer
	online_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(online_list)
	column.add_child(scroll)
	left.add_child(online)

	var playing := UI.panel(14)
	var playing_column := UI.vbox(10)
	playing.add_child(playing_column)
	var playing_header := UI.section_header("Oyun Oynayanlar", "", 18, "gamepad", UI.GREEN)
	UI.named(playing_header.get_node("Title"), "PlayingTitle")
	playing_column.add_child(playing_header)
	playing_column.add_child(UI.named(UI.hbox(14), "PlayingRow"))
	left.add_child(playing)
	return left


func _render() -> void:
	_render_online()
	_render_playing()
	_render_requests()


## Called by the top bar search while Arkadaşlar is open.
func set_query(query: String) -> void:
	_query = query.strip_edges()
	_user_results.clear()
	if _query.length() >= 2:
		_search_timer.start()
	_render_online()


func _render_search() -> void:
	var needle := _query.to_lower()
	(%OnlineToggle as Control).visible = false
	var friends := _friends().filter(func(p): return typeof(p) == TYPE_DICTIONARY and str(p.get("display_name", "")).to_lower().contains(needle))
	_online_title.text = "Arama: “%s”" % _query
	if not friends.is_empty():
		_online_list.add_child(UI.label("ARKADAŞLARIN", 12, UI.TEXT_3, true))
		for profile in friends:
			_online_list.add_child(_friend_row(profile))
	var others := _user_results.filter(func(p): return typeof(p) == TYPE_DICTIONARY and str(p.get("relationship", "")) != "friend")
	if not others.is_empty():
		_online_list.add_child(UI.label("PARDEX KULLANICILARI", 12, UI.TEXT_3, true))
		for profile in others:
			var holder := UI.panel(0, UI.box(Color(UI.SURFACE_2, 0.55), 10, UI.BORDER, 1, 8))
			holder.add_child(_user_result_row(profile))
			_online_list.add_child(holder)
	if friends.is_empty() and others.is_empty():
		var hint := "Aranıyor..." if _query.length() >= 2 and PardexOnline.is_online() else "En az 2 karakter yaz."
		if not PardexOnline.is_online():
			hint = "Kullanıcı aramak için PARDEX Online bağlantısı gerekli."
		_online_list.add_child(UI.empty_state("search", "Sonuç yok", hint, true))


func _render_online() -> void:
	UI.clear(_online_list)
	if not _query.is_empty():
		_render_search()
		return
	var friends := _friends()
	var shown := friends.filter(func(p): return typeof(p) == TYPE_DICTIONARY and (_show_all or _presence(p) != "offline"))
	var online_count := friends.filter(func(p): return typeof(p) == TYPE_DICTIONARY and _presence(p) != "offline").size()
	_online_title.text = ("Tüm Arkadaşlar (%d)" % friends.size()) if _show_all else ("Çevrimiçi (%d)" % online_count)
	# "Tümünü Gör" only makes sense once there are friends to list.
	(%OnlineToggle as Control).visible = not friends.is_empty()
	if friends.is_empty():
		var message := "PARDEX Online bağlantısı bekleniyor" if not PardexOnline.is_online() else "Henüz arkadaşın yok"
		_online_list.add_child(UI.empty_state("friends", message, "‘Arkadaş Ekle’ ile PARDEX kullanıcılarını bul.", true))
		return
	if shown.is_empty():
		_online_list.add_child(UI.empty_state("friends", "Şu an çevrimiçi arkadaşın yok", "", true))
		return
	for profile in shown:
		_online_list.add_child(_friend_row(profile))


func _picture(profile: Dictionary) -> Texture2D:
	return PardexOnline.avatar_texture(str(profile.get("account_id", "")), str(profile.get("avatar_id", "")))


func _friend_row(profile: Dictionary) -> Control:
	var account_id := str(profile.get("account_id", ""))
	var display_name := str(profile.get("display_name", "Pardus"))
	var presence := _presence(profile)
	var holder := UI.panel(0, UI.box(Color(UI.SURFACE_2, 0.55), 10, UI.BORDER, 1, 8))
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	holder.tooltip_text = "%s ile mesajlaş" % display_name
	holder.gui_input.connect(func(event: InputEvent):
		var mouse := event as InputEventMouseButton
		if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			message_requested.emit(account_id)
	)
	var row := UI.hbox(10)
	holder.add_child(row)
	row.add_child(UI.avatar(display_name, 42, presence, Color.TRANSPARENT, _picture(profile)))
	var text := UI.vbox(1)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.expand(text)
	text.add_child(UI.fit(UI.label(display_name, 14, UI.TEXT, true)))
	# Second line: the game for friends playing or in a party, else presence.
	var game_name := str(profile.get("game_name", ""))
	var detail := game_name if not game_name.is_empty() and (presence == "in_game" or bool(profile.get("in_room", false))) else UI.presence_label(presence)
	var status := UI.fit(UI.label("●  " + detail, 12, UI.presence_color(presence) if presence != "offline" else UI.TEXT_3))
	var unread := int(profile.get("chat_unread", 0))
	if unread > 0:
		status = UI.fit(UI.label("✉  %d yeni mesaj" % unread, 12, UI.ACCENT, true))
	text.add_child(status)
	row.add_child(text)
	var action := _row_action(profile)
	if action != null:
		row.add_child(action)
	var more := UI.icon_button("dots", "Seçenekler", 32)
	more.pressed.connect(func(): _open_friend_menu(profile, more))
	row.add_child(more)
	return holder


# The one room action that fits this friend right now.
func _row_action(profile: Dictionary) -> Button:
	var account_id := str(profile.get("account_id", ""))
	if bool(profile.get("room_joinable", false)) and not _friend_in_my_room(account_id):
		var join := UI.button("Katıl", "ghost", 12, 34, "gamepad")
		join.add_theme_stylebox_override("normal", UI.box(Color(UI.ACCENT_DARK, 0.55), 9, UI.ACCENT, 1))
		join.custom_minimum_size.x = ROW_ACTION_WIDTH
		join.pressed.connect(func(): PardexOnline.join_friend_room(account_id))
		return join
	# Offline friends get the message when they come back.
	var message := UI.button("Mesaj", "ghost", 12, 34, "message")
	message.custom_minimum_size.x = ROW_ACTION_WIDTH
	message.pressed.connect(func(): message_requested.emit(account_id))
	return message


func _render_playing() -> void:
	UI.clear(_playing_row)
	var playing := _friends().filter(func(p): return typeof(p) == TYPE_DICTIONARY and _presence(p) == "in_game")
	_playing_title.text = "Oyun Oynayanlar (%d)" % playing.size()
	if playing.is_empty():
		_playing_row.add_child(UI.expand(UI.empty_state("gamepad", "Şu an oyunda arkadaşın yok", "", true)))
		return
	for profile in playing.slice(0, 5):
		var cell := UI.vbox(4)
		cell.custom_minimum_size.x = 84
		var center := CenterContainer.new()
		center.add_child(UI.avatar(str(profile.get("display_name", "P")), 56, "in_game", UI.ACCENT, _picture(profile)))
		cell.add_child(center)
		var name_label := UI.fit(UI.label(str(profile.get("display_name", "")), 13, UI.TEXT, true))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(name_label)
		var game_label := UI.fit(UI.label(str(profile.get("game_name", "")), 11, UI.TEXT_2))
		game_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(game_label)
		_playing_row.add_child(cell)


# ------------------------------------------------------------------ chat

# ------------------------------------------------------------------ right column

func _build_right() -> Control:
	var right := UI.named(UI.vbox(16), "RightColumn") as VBoxContainer
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var requests := UI.panel(16)
	requests.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var requests_column := UI.vbox(10)
	requests.add_child(requests_column)
	var header := UI.section_header("Arkadaşlık İstekleri", "", 18)
	UI.named(header.get_node("Title"), "RequestsTitle")
	requests_column.add_child(header)
	requests_column.add_child(UI.named(UI.vbox(10), "RequestsList"))
	right.add_child(requests)

	return right


func _render_requests() -> void:
	UI.clear(_requests_list)
	var incoming := _requests("incoming_requests")
	_requests_title.text = "Arkadaşlık İstekleri (%d)" % incoming.size()
	if incoming.is_empty():
		_requests_list.add_child(UI.empty_state("mail", "Bekleyen arkadaşlık isteği yok", "", true))
		return
	for profile in incoming.slice(0, 3):
		if typeof(profile) != TYPE_DICTIONARY:
			continue
		var account_id := str(profile.get("account_id", ""))
		var row := UI.hbox(10)
		row.add_child(UI.avatar(str(profile.get("display_name", "P")), 44, _presence(profile), Color.TRANSPARENT, _picture(profile)))
		var text := UI.vbox(1)
		UI.expand(text)
		text.add_child(UI.fit(UI.label(str(profile.get("display_name", "Pardus")), 14, UI.TEXT, true)))
		text.add_child(UI.fit(UI.label("Sana arkadaşlık isteği gönderdi.", 11, UI.TEXT_2)))
		row.add_child(text)
		var accept := UI.button("Kabul Et", "primary", 12, 34)
		accept.pressed.connect(func(): PardexOnline.accept_friend_request(account_id))
		row.add_child(accept)
		var decline := UI.button("Reddet", "ghost", 12, 34)
		decline.pressed.connect(func(): PardexOnline.decline_friend_request(account_id))
		row.add_child(decline)
		_requests_list.add_child(row)


# ------------------------------------------------------------------ menus + dialogs

func _bind_friend_menu() -> void:
	_friend_menu = %FriendMenu
	_friend_menu.id_pressed.connect(func(id: int):
		match id:
			1: PardexOnline.join_friend_room(_menu_account_id)
			2: PardexOnline.remove_friend(_menu_account_id)
	)


func _open_friend_menu(profile: Dictionary, anchor: Control) -> void:
	_menu_account_id = str(profile.get("account_id", ""))
	_friend_menu.clear()
	_friend_menu.add_item("Masasına katıl", 1)
	_friend_menu.set_item_disabled(1, not bool(profile.get("room_joinable", false)))
	_friend_menu.add_separator()
	_friend_menu.add_item("Arkadaşlıktan çıkar", 2)
	var rect := anchor.get_global_rect()
	_friend_menu.popup(Rect2i(Vector2i(rect.position + Vector2(0, rect.size.y)), Vector2i.ZERO))


func _bind_add_dialog() -> void:
	_add_dialog = %AddFriendDialog
	_add_hint = %AddFriendHint
	_add_results = %AddFriendResults
	var field := %AddFriendField as LineEdit
	(%AddFriendGo as Button).pressed.connect(func(): _search_users(field.text))
	field.text_submitted.connect(_search_users)


func _search_users(text: String) -> void:
	var query := text.strip_edges()
	if query.length() < 2:
		_add_hint.text = "En az 2 karakter yaz."
		return
	_last_search = query
	_add_hint.text = "Aranıyor..."
	PardexOnline.search_users(query)


func _open_add_dialog() -> void:
	if not PardexOnline.is_online():
		toast.emit("Arkadaş eklemek için PARDEX Online bağlantısı gerekli.")
		return
	_add_dialog.popup_centered()


func _on_search_results(results: Array) -> void:
	UI.clear(_add_results)
	_add_hint.text = "%d kullanıcı bulundu." % results.size() if not results.is_empty() else "'%s' için kullanıcı bulunamadı." % _last_search
	if not _query.is_empty():
		_user_results = results.duplicate(true)
		_render_online()
	for profile in results:
		if typeof(profile) == TYPE_DICTIONARY:
			_add_results.add_child(_user_result_row(profile))


func _user_result_row(profile: Dictionary) -> Control:
	var account_id := str(profile.get("account_id", ""))
	var row := UI.hbox(10)
	row.add_child(UI.avatar(str(profile.get("display_name", "P")), 36, _presence(profile), Color.TRANSPARENT, _picture(profile)))
	var text := UI.vbox(0)
	UI.expand(text)
	text.add_child(UI.label(str(profile.get("display_name", "Pardus")), 13, UI.TEXT, true))
	text.add_child(UI.label("#" + str(profile.get("tag", account_id.right(6).to_upper())), 11, UI.TEXT_3))
	row.add_child(text)
	var action: Button
	match str(profile.get("relationship", "none")):
		"friend":
			action = UI.button("Arkadaşsınız", "ghost", 11, 32)
			action.disabled = true
		"incoming":
			action = UI.button("Kabul Et", "primary", 11, 32)
			action.pressed.connect(func(): PardexOnline.accept_friend_request(account_id))
		"outgoing":
			action = UI.button("İsteği İptal Et", "ghost", 11, 32)
			action.pressed.connect(func(): PardexOnline.cancel_friend_request(account_id))
		_:
			action = UI.button("Ekle", "primary", 11, 32, "user_plus")
			action.pressed.connect(func(): PardexOnline.send_friend_request(account_id))
	row.add_child(action)
	return row


func _on_connection_state_changed(state: String) -> void:
	if state == "online":
		PardexOnline.request_social_state()
	_render()


func _bind_invite_dialog() -> void:
	_invite_dialog = %InviteDialog
	_invite_dialog.confirmed.connect(func():
		if not _active_invite_id.is_empty():
			PardexOnline.accept_room_invite(_active_invite_id)
			_active_invite_id = ""
	)
	_invite_dialog.canceled.connect(func():
		if not _active_invite_id.is_empty():
			PardexOnline.decline_room_invite(_active_invite_id)
			_active_invite_id = ""
	)


func _on_room_invite_received(invite: Dictionary) -> void:
	var invite_id := str(invite.get("id", ""))
	if invite_id.is_empty():
		return
	if not _active_invite_id.is_empty() and _active_invite_id != invite_id:
		PardexOnline.decline_room_invite(_active_invite_id)
	_active_invite_id = invite_id
	_invite_dialog.dialog_text = "%s seni %s masasına davet ediyor.\nKatılırsan oyun masada açılır.\n\nMasa kodu: %s   •   Oyuncular: %d / %d" % [
		str(invite.get("from_display_name", "Bir arkadaşın")),
		str(invite.get("game_name", "PARDEX Oyunu")),
		str(invite.get("room_code", "")),
		int(invite.get("member_count", 0)),
		int(invite.get("max_players", 0)),
	]
	_invite_dialog.popup_centered()


func _on_room_invite_closed(invite_id: String, reason: String) -> void:
	if invite_id != _active_invite_id:
		return
	var was_visible := _invite_dialog.visible
	_active_invite_id = ""
	_invite_dialog.hide()
	if was_visible and reason == "expired":
		toast.emit("Oyun davetinin süresi doldu.")
	elif was_visible and reason in ["room_closed", "room_full", "room_in_game"]:
		toast.emit("Davet edilen maç başladı ya da doldu.")
