extends VBoxContainer

# Arkadaşlar / Sohbet: friend list with tabs, a conversation panel and the
# game party / voice cards. Friends, requests, presence, rooms and invites are
# live PARDEX Online data. Messaging and voice have no server support yet, so
# those panels say so instead of showing made-up conversations.

signal navigate(page: String)
signal toast(message: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")

const TABS := [["all", "Tümü"], ["online", "Çevrimiçi"], ["in_game", "Oyunlarda"], ["pending", "Bekleyenler"]]

var _tab := "all"
var _tab_buttons: Dictionary = {}
var _filter := ""
var _selected_id := ""
var _columns: HBoxContainer
var _list_panel: Control
var _list: VBoxContainer
var _chat_panel: Control
var _chat_header: HBoxContainer
var _chat_body: VBoxContainer
var _right_column: Control
var _party_card: VBoxContainer
var _friend_menu: PopupMenu
var _menu_account_id := ""
var _add_dialog: AcceptDialog
var _add_results: VBoxContainer
var _add_hint: Label
var _last_search := ""
var _invite_dialog: ConfirmationDialog
var _active_invite_id := ""


func _ready() -> void:
	add_theme_constant_override("separation", 12)

	var header := UI.hbox(12)
	add_child(header)
	var titles := UI.vbox(2)
	UI.expand(titles)
	titles.add_child(UI.label("Arkadaşlar  /  Sohbet", 26, UI.TEXT, true))
	titles.add_child(UI.label("Oyunlar daha güzel, birlikte oynayınca.", 13, UI.TEXT_2))
	header.add_child(titles)
	var add_button := UI.button("+  Arkadaş Ekle", "primary", 13, 38)
	add_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_button.pressed.connect(_open_add_dialog)
	header.add_child(add_button)

	var tabs := UI.hbox(4)
	add_child(tabs)
	for entry in TABS:
		var tab_button := _tab_button(str(entry[1]))
		tab_button.pressed.connect(_select_tab.bind(str(entry[0])))
		tabs.add_child(tab_button)
		_tab_buttons[entry[0]] = tab_button

	_columns = UI.hbox(12)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_columns)
	_columns.add_child(_build_list_panel())
	_columns.add_child(_build_chat_panel())
	_columns.add_child(_build_right_column())

	_build_friend_menu()
	_build_add_dialog()
	_build_invite_dialog()

	PardexOnline.social_state_changed.connect(func(_state): _render())
	PardexOnline.connection_state_changed.connect(_on_connection_state_changed)
	PardexOnline.room_state_changed.connect(func(_room): _render())
	PardexOnline.room_left.connect(_render)
	PardexOnline.user_search_results.connect(_on_search_results)
	PardexOnline.social_notice.connect(func(message: String): toast.emit(message))
	PardexOnline.room_invite_received.connect(_on_room_invite_received)
	PardexOnline.room_invite_closed.connect(_on_room_invite_closed)
	if PardexOnline.is_online():
		PardexOnline.request_social_state()
	_render()


func apply_layout(content_width: float) -> void:
	_right_column.visible = content_width >= 900.0
	_chat_panel.visible = content_width >= 640.0
	_list_panel.size_flags_horizontal = Control.SIZE_FILL if _chat_panel.visible else Control.SIZE_EXPAND_FILL
	_list_panel.custom_minimum_size.x = clampf(content_width * 0.27, 230.0, 300.0) if _chat_panel.visible else 0.0
	_right_column.custom_minimum_size.x = clampf(content_width * 0.24, 220.0, 280.0)


# ---------------------------------------------------------------- data

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
	if presence == "in_game" and not game_name.is_empty():
		return game_name + " oynuyor"
	if bool(profile.get("in_room", false)) and not game_name.is_empty():
		return "%s odasında  %d/%d" % [game_name, int(profile.get("room_member_count", 0)), int(profile.get("room_max_players", 0))]
	return UI.presence_label(presence)


func _find_friend(account_id: String) -> Dictionary:
	for profile in _friends():
		if typeof(profile) == TYPE_DICTIONARY and str(profile.get("account_id", "")) == account_id:
			return profile
	return {}


# ---------------------------------------------------------------- tabs + list

func _tab_button(text: String) -> Button:
	var item := Button.new()
	item.text = text
	item.toggle_mode = true
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size.y = 34
	item.add_theme_font_size_override("font_size", 13)
	var normal := UI.box(Color.TRANSPARENT, 0)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var active := normal.duplicate() as StyleBoxFlat
	active.border_color = UI.ACCENT
	active.border_width_bottom = 2
	active.bg_color = Color(UI.ACCENT, 0.08)
	for state in ["normal", "hover"]:
		item.add_theme_stylebox_override(state, normal)
	for state in ["pressed", "hover_pressed"]:
		item.add_theme_stylebox_override(state, active)
	item.add_theme_color_override("font_color", UI.TEXT_2)
	item.add_theme_color_override("font_hover_color", UI.TEXT)
	item.add_theme_color_override("font_pressed_color", UI.ACCENT)
	item.add_theme_color_override("font_hover_pressed_color", UI.ACCENT)
	return item


func _select_tab(tab: String) -> void:
	_tab = tab
	_render()


func _build_list_panel() -> Control:
	_list_panel = UI.panel(10)
	_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(8)
	_list_panel.add_child(column)
	var search := UI.search_field("Arkadaş listesinde ara...", 34)
	search.text_changed.connect(func(value: String):
		_filter = value.strip_edges().to_lower()
		_render_list()
	)
	column.add_child(search)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = UI.vbox(2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	return _list_panel


func _render() -> void:
	var friends := _friends()
	var counts := {"all": friends.size(), "online": 0, "in_game": 0,
		"pending": _requests("incoming_requests").size() + _requests("outgoing_requests").size()}
	for profile in friends:
		if typeof(profile) != TYPE_DICTIONARY:
			continue
		var presence := _presence(profile)
		if presence != "offline":
			counts["online"] += 1
		if presence == "in_game":
			counts["in_game"] += 1
	for entry in TABS:
		var tab_button := _tab_buttons[entry[0]] as Button
		tab_button.text = "%s   %d" % [entry[1], counts[entry[0]]]
		tab_button.set_pressed_no_signal(entry[0] == _tab)
	if _selected_id.is_empty() or _find_friend(_selected_id).is_empty():
		_selected_id = ""
		for profile in friends:
			if typeof(profile) == TYPE_DICTIONARY:
				_selected_id = str(profile.get("account_id", ""))
				break
	_render_list()
	_render_chat()
	_render_party()


func _render_list() -> void:
	UI.clear(_list)
	if not PardexOnline.is_online() and _friends().is_empty():
		_list.add_child(UI.empty_state("⚡", "PARDEX Online bağlantısı bekleniyor", "Arkadaş listen bağlantı kurulunca yüklenir."))
		return
	if _tab == "pending":
		_render_pending()
		return
	var shown := 0
	for profile in _friends():
		if typeof(profile) != TYPE_DICTIONARY:
			continue
		var presence := _presence(profile)
		if _tab == "online" and presence == "offline":
			continue
		if _tab == "in_game" and presence != "in_game":
			continue
		if not _filter.is_empty() and not (_filter in str(profile.get("display_name", "")).to_lower()):
			continue
		_list.add_child(_friend_row(profile))
		shown += 1
	if shown == 0:
		var message := "Henüz arkadaşın yok" if _friends().is_empty() else "Bu listede kimse yok"
		_list.add_child(UI.empty_state("◎", message, "‘Arkadaş Ekle’ ile PARDEX kullanıcılarını bul." if _friends().is_empty() else ""))


func _friend_row(profile: Dictionary) -> Control:
	var account_id := str(profile.get("account_id", ""))
	var name := str(profile.get("display_name", "Pardus"))
	var selected := account_id == _selected_id
	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.custom_minimum_size.y = 50
	var normal := UI.box(Color(UI.ACCENT, 0.12) if selected else Color.TRANSPARENT, 8)
	var hover := UI.box(Color(UI.ACCENT, 0.16) if selected else Color(1, 1, 1, 0.04), 8)
	row.add_theme_stylebox_override("normal", normal)
	row.add_theme_stylebox_override("hover", hover)
	row.add_theme_stylebox_override("pressed", hover)
	row.pressed.connect(func():
		_selected_id = account_id
		_render_list()
		_render_chat()
	)
	var line := UI.hbox(10)
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8
	line.offset_right = -4
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var avatar := UI.avatar(name, 36, _presence(profile))
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(avatar)
	var text := UI.vbox(0)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.expand(text)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(UI.fit(UI.label(name, 13, UI.TEXT, true)))
	text.add_child(UI.fit(UI.label(_activity(profile), 11, UI.presence_color(_presence(profile)) if _presence(profile) == "in_game" else UI.TEXT_3)))
	line.add_child(text)
	var more := UI.icon_button("⋮", "Seçenekler", 28)
	more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	more.pressed.connect(func(): _open_friend_menu(profile, more))
	line.add_child(more)
	return row


func _render_pending() -> void:
	var incoming := _requests("incoming_requests")
	var outgoing := _requests("outgoing_requests")
	if incoming.is_empty() and outgoing.is_empty():
		_list.add_child(UI.empty_state("✉", "Bekleyen istek yok"))
		return
	for profile in incoming:
		if typeof(profile) == TYPE_DICTIONARY:
			var account_id := str(profile.get("account_id", ""))
			_list.add_child(_request_row(profile, "Sana istek gönderdi", [
				["Kabul", "primary", func(): PardexOnline.accept_friend_request(account_id)],
				["Reddet", "ghost", func(): PardexOnline.decline_friend_request(account_id)],
			]))
	for profile in outgoing:
		if typeof(profile) == TYPE_DICTIONARY:
			var account_id := str(profile.get("account_id", ""))
			_list.add_child(_request_row(profile, "İstek gönderildi", [
				["İptal", "ghost", func(): PardexOnline.cancel_friend_request(account_id)],
			]))


func _request_row(profile: Dictionary, note: String, actions: Array) -> Control:
	var name := str(profile.get("display_name", "Pardus"))
	var holder := UI.panel(0, UI.box(Color.TRANSPARENT, 8, Color.TRANSPARENT, 0, 6))
	var column := UI.vbox(6)
	holder.add_child(column)
	var line := UI.hbox(10)
	column.add_child(line)
	line.add_child(UI.avatar(name, 34, _presence(profile)))
	var text := UI.vbox(0)
	UI.expand(text)
	text.add_child(UI.label(name, 13, UI.TEXT, true))
	text.add_child(UI.label(note, 11, UI.TEXT_3))
	line.add_child(text)
	var buttons := UI.hbox(6)
	column.add_child(buttons)
	for action in actions:
		var item := UI.button(str(action[0]), str(action[1]), 11, 28)
		UI.expand(item)
		item.pressed.connect(action[2])
		buttons.add_child(item)
	return holder


# ---------------------------------------------------------------- chat

func _build_chat_panel() -> Control:
	_chat_panel = UI.panel(0)
	UI.expand(_chat_panel)
	_chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(0)
	_chat_panel.add_child(column)
	var header_box := UI.panel(0, UI.box(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 12))
	column.add_child(header_box)
	_chat_header = UI.hbox(10)
	header_box.add_child(_chat_header)
	var divider := ColorRect.new()
	divider.color = UI.BORDER
	divider.custom_minimum_size.y = 1
	column.add_child(divider)
	_chat_body = UI.vbox(10)
	_chat_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		body_margin.add_theme_constant_override("margin_" + side, 16)
	body_margin.add_child(_chat_body)
	column.add_child(body_margin)
	var input_margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		input_margin.add_theme_constant_override("margin_" + side, 12)
	column.add_child(input_margin)
	var input_row := UI.hbox(8)
	input_margin.add_child(input_row)
	var input := LineEdit.new()
	input.placeholder_text = "Mesaj yaz...  (mesajlaşma yakında)"
	input.editable = false
	input.custom_minimum_size.y = 38
	input.add_theme_font_size_override("font_size", 13)
	input.add_theme_color_override("font_placeholder_color", UI.TEXT_3)
	input.add_theme_stylebox_override("read_only", UI.box(UI.SURFACE_2, 9, UI.BORDER, 1, 10))
	UI.expand(input)
	input_row.add_child(input)
	var send := UI.icon_button("➤", "Gönder", 38)
	send.disabled = true
	input_row.add_child(send)
	return _chat_panel


func _render_chat() -> void:
	UI.clear(_chat_header)
	UI.clear(_chat_body)
	var profile := _find_friend(_selected_id)
	if profile.is_empty():
		_chat_header.add_child(UI.label("Sohbet", 14, UI.TEXT, true))
		_chat_body.add_child(UI.empty_state("💬", "Bir arkadaş seç", "Arkadaşlarını soldaki listeden seçebilirsin."))
		return
	var name := str(profile.get("display_name", "Pardus"))
	_chat_header.add_child(UI.avatar(name, 38, _presence(profile)))
	var titles := UI.vbox(0)
	UI.expand(titles)
	titles.add_child(UI.fit(UI.label(name, 14, UI.TEXT, true)))
	titles.add_child(UI.fit(UI.label(_activity(profile), 11, UI.TEXT_3)))
	_chat_header.add_child(titles)
	for glyph in [["✆", "Sesli arama yakında"], ["▣", "Görüntülü arama yakında"]]:
		var item := UI.icon_button(str(glyph[0]), str(glyph[1]), 32)
		item.disabled = true
		_chat_header.add_child(item)
	var more := UI.icon_button("⋯", "Seçenekler", 32)
	more.pressed.connect(func(): _open_friend_menu(profile, more))
	_chat_header.add_child(more)

	_chat_body.add_child(UI.empty_state("💬", "%s ile sohbet yakında" % name,
		"PARDEX mesajlaşması henüz hazır değil. Şimdilik birlikte oynamak için odana davet edebilir ya da odasına katılabilirsin."))
	var action := _room_action(profile)
	if action != null:
		var holder := CenterContainer.new()
		holder.add_child(action)
		_chat_body.add_child(holder)


# The one room action that makes sense for this friend right now.
func _room_action(profile: Dictionary) -> Button:
	var account_id := str(profile.get("account_id", ""))
	var presence := _presence(profile)
	var room := PardexOnline.current_room
	if _friend_in_my_room(account_id):
		var same := UI.button("Aynı odadasınız", "ghost", 12, 34)
		same.disabled = true
		return same
	if bool(profile.get("room_joinable", false)):
		var join := UI.button("Odasına Katıl", "primary", 12, 34)
		join.pressed.connect(func(): PardexOnline.join_friend_room(account_id))
		return join
	if presence != "offline" and not room.is_empty() and not bool(room.get("launching", false)):
		var invite := UI.button("Odama Davet Et", "primary", 12, 34)
		invite.pressed.connect(func(): PardexOnline.send_room_invite(account_id))
		return invite
	return null


func _friend_in_my_room(account_id: String) -> bool:
	var members = PardexOnline.current_room.get("members", [])
	if typeof(members) != TYPE_ARRAY:
		return false
	for member in members:
		if typeof(member) == TYPE_DICTIONARY and str(member.get("account_id", "")) == account_id:
			return true
	return false


# ---------------------------------------------------------------- party + voice

func _build_right_column() -> Control:
	var column := UI.vbox(12)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_column = column

	var party := UI.panel(12)
	_party_card = UI.vbox(10)
	party.add_child(_party_card)
	column.add_child(party)

	var voice := UI.panel(12)
	var voice_column := UI.vbox(8)
	voice.add_child(voice_column)
	voice_column.add_child(UI.label("Aktif Ses Odası", 14, UI.ACCENT, true))
	var line := UI.hbox(10)
	voice_column.add_child(line)
	var icon := UI.panel(0, UI.box(UI.SURFACE_2, 8, UI.BORDER, 1, 6))
	icon.add_child(UI.label("🎧", 14, UI.TEXT_2))
	line.add_child(icon)
	var text := UI.vbox(0)
	text.add_child(UI.label("Genel Sohbet", 13, UI.TEXT, true))
	text.add_child(UI.label("Sesli sohbet yakında", 11, UI.TEXT_3))
	line.add_child(text)
	var join_voice := UI.button("Sese Katıl", "ghost", 12, 36)
	join_voice.disabled = true
	join_voice.tooltip_text = "PARDEX sesli sohbeti henüz hazır değil."
	voice_column.add_child(join_voice)
	column.add_child(voice)
	return column


func _render_party() -> void:
	UI.clear(_party_card)
	_party_card.add_child(UI.label("Oyun Partisi", 14, UI.TEXT, true))
	var game := Catalog.game("korsanlar")
	var art := UI.image(Catalog.texture(str(game["banner"])), Vector2(0, 92), 8)
	_party_card.add_child(art)
	var room := PardexOnline.current_room
	var members: Array = room.get("members", []) if typeof(room.get("members", [])) == TYPE_ARRAY else []
	var avatars := UI.hbox(6)
	for member in members:
		if typeof(member) == TYPE_DICTIONARY:
			avatars.add_child(UI.avatar(str(member.get("display_name", "P")), 30, "online" if bool(member.get("ready", false)) else "", UI.SURFACE))
	var free_slots := int(room.get("max_players", 4)) - members.size() if not room.is_empty() else 4
	for _slot in maxi(0, free_slots):
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(30, 30)
		slot.add_theme_stylebox_override("panel", UI.box(Color.TRANSPARENT, 15, UI.BORDER_HI, 1))
		avatars.add_child(slot)
	_party_card.add_child(avatars)

	var action_row := UI.hbox(6)
	if room.is_empty():
		_party_card.add_child(UI.label(str(game["title"]), 13, UI.TEXT, true))
		_party_card.add_child(UI.label("Parti kur, arkadaşlarını davet et.", 11, UI.TEXT_3))
		var create := UI.button("Parti Kur", "gold", 13, 38)
		create.disabled = not PardexOnline.is_online()
		create.pressed.connect(func(): PardexOnline.create_room("korsanlar", 4))
		action_row.add_child(UI.expand(create))
	else:
		var ready := 0
		for member in members:
			if typeof(member) == TYPE_DICTIONARY and bool(member.get("ready", false)):
				ready += 1
		_party_card.add_child(UI.label("%s  •  Oda %s" % [str(game["title"]), str(room.get("code", ""))], 13, UI.TEXT, true))
		_party_card.add_child(UI.label("%d/%d oyuncu hazır" % [ready, int(room.get("max_players", 4))], 11, UI.TEXT_3))
		var manage := UI.button("Partiyi Yönet", "gold", 13, 38)
		manage.pressed.connect(func(): navigate.emit("rooms"))
		action_row.add_child(UI.expand(manage))
	var more := UI.button("▾", "ghost", 12, 38)
	more.custom_minimum_size.x = 38
	more.tooltip_text = "Oda koduyla katıl"
	more.pressed.connect(func(): navigate.emit("rooms"))
	action_row.add_child(more)
	_party_card.add_child(action_row)


# ---------------------------------------------------------------- menus + dialogs

func _build_friend_menu() -> void:
	_friend_menu = PopupMenu.new()
	add_child(_friend_menu)
	_friend_menu.id_pressed.connect(func(id: int):
		match id:
			0: PardexOnline.send_room_invite(_menu_account_id)
			1: PardexOnline.join_friend_room(_menu_account_id)
			2: PardexOnline.remove_friend(_menu_account_id)
	)


func _open_friend_menu(profile: Dictionary, anchor: Control) -> void:
	_menu_account_id = str(profile.get("account_id", ""))
	_friend_menu.clear()
	var room := PardexOnline.current_room
	_friend_menu.add_item("Odama davet et", 0)
	_friend_menu.set_item_disabled(0, room.is_empty() or _presence(profile) == "offline" or _friend_in_my_room(_menu_account_id))
	_friend_menu.add_item("Odasına katıl", 1)
	_friend_menu.set_item_disabled(1, not bool(profile.get("room_joinable", false)))
	_friend_menu.add_separator()
	_friend_menu.add_item("Arkadaşlıktan çıkar", 2)
	var rect := anchor.get_global_rect()
	_friend_menu.popup(Rect2i(Vector2i(rect.position + Vector2(0, rect.size.y)), Vector2i.ZERO))


func _build_add_dialog() -> void:
	_add_dialog = AcceptDialog.new()
	_add_dialog.title = "Arkadaş Ekle"
	_add_dialog.ok_button_text = "Kapat"
	_add_dialog.min_size = Vector2i(460, 420)
	add_child(_add_dialog)
	var column := UI.vbox(10)
	_add_dialog.add_child(column)
	var search_row := UI.hbox(8)
	column.add_child(search_row)
	var field := UI.search_field("Kullanıcı adı veya PARDEX kimliği...", 38)
	UI.expand(field)
	search_row.add_child(field)
	var go := UI.button("Ara", "primary", 13, 38)
	search_row.add_child(go)
	go.pressed.connect(func(): _search_users(field.text))
	field.text_submitted.connect(_search_users)
	_add_hint = UI.label("PARDEX kullanıcılarını adıyla bul.", 12, UI.TEXT_3)
	column.add_child(_add_hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 260
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_add_results = UI.vbox(6)
	_add_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_add_results)


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
	for profile in results:
		if typeof(profile) != TYPE_DICTIONARY:
			continue
		var account_id := str(profile.get("account_id", ""))
		var relationship := str(profile.get("relationship", "none"))
		var row := UI.hbox(10)
		row.add_child(UI.avatar(str(profile.get("display_name", "P")), 34, _presence(profile)))
		var text := UI.vbox(0)
		UI.expand(text)
		text.add_child(UI.label(str(profile.get("display_name", "Pardus")), 13, UI.TEXT, true))
		text.add_child(UI.label("#" + str(profile.get("tag", account_id.right(6).to_upper())), 11, UI.TEXT_3))
		row.add_child(text)
		var action: Button
		match relationship:
			"friend":
				action = UI.button("Arkadaşsınız", "ghost", 11, 30)
				action.disabled = true
			"incoming":
				action = UI.button("Kabul Et", "primary", 11, 30)
				action.pressed.connect(func(): PardexOnline.accept_friend_request(account_id))
			"outgoing":
				action = UI.button("İsteği İptal Et", "ghost", 11, 30)
				action.pressed.connect(func(): PardexOnline.cancel_friend_request(account_id))
			_:
				action = UI.button("Ekle", "primary", 11, 30)
				action.pressed.connect(func(): PardexOnline.send_friend_request(account_id))
		row.add_child(action)
		_add_results.add_child(row)


func _on_connection_state_changed(state: String) -> void:
	if state == "online":
		PardexOnline.request_social_state()
	_render()


func _build_invite_dialog() -> void:
	_invite_dialog = ConfirmationDialog.new()
	_invite_dialog.title = "PARDEX Oda Daveti"
	_invite_dialog.ok_button_text = "Katıl"
	_invite_dialog.cancel_button_text = "Reddet"
	_invite_dialog.min_size = Vector2i(460, 200)
	_invite_dialog.exclusive = true
	add_child(_invite_dialog)
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
	_invite_dialog.dialog_text = "%s seni %s odasına davet ediyor.\n\nOda: %s   •   Oyuncular: %d / %d" % [
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
		toast.emit("Oda davetinin süresi doldu.")
	elif was_visible and reason in ["room_closed", "room_full", "room_in_game"]:
		toast.emit("Davet edilen oda artık katılıma uygun değil.")
