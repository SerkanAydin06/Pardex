extends VBoxContainer

# Arkadaşlar: hero, online friends, friends in game, conversation panel, the
# party card (PARDEX Online rooms), pending requests and suggestions.
#
# The party card is the whole room flow — create, join by code, share the
# code, invite friends, ready up, start the game and leave — so PARDEX needs
# no separate "Odalar" tab. Friends, presence, requests, invites and rooms are
# live data; messaging, voice and friend suggestions have no server support
# yet and say so.

signal toast(message: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")
const HERO_HEIGHT := 300.0

var _show_all := false
var _selected_id := ""
var _columns: HBoxContainer
var _left: VBoxContainer
var _online_title: Label
var _online_list: VBoxContainer
var _playing_title: Label
var _playing_row: HBoxContainer
var _chat_panel: Control
var _chat_header: HBoxContainer
var _chat_body: VBoxContainer
var _right: VBoxContainer
var _party: VBoxContainer
var _requests_title: Label
var _requests_list: VBoxContainer
var _hero_bullets: Control
var _friend_menu: PopupMenu
var _menu_account_id := ""
var _add_dialog: AcceptDialog
var _add_results: VBoxContainer
var _add_hint: Label
var _last_search := ""
var _code_dialog: ConfirmationDialog
var _code_edit: LineEdit
var _invite_picker: PopupMenu
var _invite_dialog: ConfirmationDialog
var _active_invite_id := ""


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	var body := UI.vbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UI.scroll_page(body))
	body.add_child(_build_hero())

	_columns = UI.hbox(16)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.custom_minimum_size.y = 560
	body.add_child(_columns)
	_columns.add_child(_build_left())
	_columns.add_child(_build_chat())
	_columns.add_child(_build_right())

	_build_friend_menu()
	_build_add_dialog()
	_build_code_dialog()
	_build_invite_dialog()
	_invite_picker = PopupMenu.new()
	add_child(_invite_picker)
	_invite_picker.index_pressed.connect(func(index: int):
		PardexOnline.send_room_invite(str(_invite_picker.get_item_metadata(index)))
	)

	PardexOnline.social_state_changed.connect(func(_state): _render())
	PardexOnline.connection_state_changed.connect(_on_connection_state_changed)
	PardexOnline.room_state_changed.connect(func(_room_state): _render())
	PardexOnline.room_left.connect(_render)
	PardexOnline.user_search_results.connect(_on_search_results)
	PardexOnline.social_notice.connect(func(message: String): toast.emit(message))
	PardexOnline.room_invite_received.connect(_on_room_invite_received)
	PardexOnline.room_invite_closed.connect(_on_room_invite_closed)
	if PardexOnline.is_online():
		PardexOnline.request_social_state()
	_render()


func apply_layout(content_width: float) -> void:
	_right.visible = content_width >= 980.0
	_chat_panel.visible = content_width >= 700.0
	_hero_bullets.visible = content_width >= 960.0
	_left.size_flags_horizontal = Control.SIZE_FILL if _chat_panel.visible else Control.SIZE_EXPAND_FILL
	_left.custom_minimum_size.x = clampf(content_width * 0.33, 300.0, 470.0) if _chat_panel.visible else 0.0
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
	var frame := UI.image(Catalog.texture("res://assets/ui/home_hero_banner.png"), Vector2(0, HERO_HEIGHT), 16)
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
	text.add_child(UI.label("Oyunlar daha eğlenceli, birlikte daha güçlü.", 16, UI.TEXT_2))
	text.add_child(UI.vspacer())
	var actions := UI.hbox(14)
	text.add_child(actions)
	var add := UI.button("Arkadaş Ekle", "primary", 15, 48, "user_plus")
	add.custom_minimum_size.x = 210
	add.pressed.connect(_open_add_dialog)
	actions.add_child(add)
	var party := UI.button("Parti Kur", "ghost", 15, 48, "friends")
	party.custom_minimum_size.x = 190
	party.pressed.connect(_create_party)
	actions.add_child(party)

	var bullets := UI.panel(0, UI.box(Color(UI.BG, 0.72), 12, UI.BORDER_HI, 1, 18))
	bullets.custom_minimum_size.x = 330
	var list := UI.vbox(14)
	list.alignment = BoxContainer.ALIGNMENT_CENTER
	bullets.add_child(list)
	for bullet in [
		["friends", "Birlikte Oyna", "Arkadaşlarını davet et, parti kur."],
		["headphones", "Sesli Sohbet", "Oyun içi sesli sohbet yakında."],
		["user_plus", "Yeni Arkadaşlar Keşfet", "PARDEX kullanıcılarını adıyla bul."],
	]:
		var line := UI.hbox(14)
		line.add_child(UI.icon(str(bullet[0]), 28, UI.ACCENT))
		var copy := UI.vbox(2)
		copy.add_child(UI.label(str(bullet[1]), 15, UI.TEXT, true))
		copy.add_child(UI.label(str(bullet[2]), 13, UI.TEXT_2))
		line.add_child(copy)
		list.add_child(line)
	_hero_bullets = bullets
	row.add_child(bullets)
	return frame


# ------------------------------------------------------------------ left column

func _build_left() -> Control:
	_left = UI.vbox(16)
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var online := UI.panel(14)
	online.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(10)
	online.add_child(column)
	var header := UI.section_header("Çevrimiçi", "Tümünü Gör", 18, "users_group", UI.GREEN)
	_online_title = header.get_node("Title") as Label
	var toggle := header.get_node("Link") as Button
	toggle.pressed.connect(func():
		_show_all = not _show_all
		toggle.text = ("Çevrimiçileri Göster" if _show_all else "Tümünü Gör") + "  "
		_render_online()
	)
	column.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_online_list = UI.vbox(6)
	_online_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_online_list)
	column.add_child(scroll)
	_left.add_child(online)

	var playing := UI.panel(14)
	var playing_column := UI.vbox(10)
	playing.add_child(playing_column)
	var playing_header := UI.section_header("Oyun Oynayanlar", "", 18, "gamepad", UI.GREEN)
	_playing_title = playing_header.get_node("Title") as Label
	playing_column.add_child(playing_header)
	_playing_row = UI.hbox(14)
	playing_column.add_child(_playing_row)
	_left.add_child(playing)
	return _left


func _render() -> void:
	var friends := _friends()
	if _selected_id.is_empty() or _find_friend(_selected_id).is_empty():
		_selected_id = ""
		for profile in friends:
			if typeof(profile) == TYPE_DICTIONARY and _presence(profile) != "offline":
				_selected_id = str(profile.get("account_id", ""))
				break
		if _selected_id.is_empty() and not friends.is_empty() and typeof(friends[0]) == TYPE_DICTIONARY:
			_selected_id = str(friends[0].get("account_id", ""))
	_render_online()
	_render_playing()
	_render_chat()
	_render_party()
	_render_requests()


func _render_online() -> void:
	UI.clear(_online_list)
	var friends := _friends()
	var shown := friends.filter(func(p): return typeof(p) == TYPE_DICTIONARY and (_show_all or _presence(p) != "offline"))
	var online_count := friends.filter(func(p): return typeof(p) == TYPE_DICTIONARY and _presence(p) != "offline").size()
	_online_title.text = ("Tüm Arkadaşlar (%d)" % friends.size()) if _show_all else ("Çevrimiçi (%d)" % online_count)
	if friends.is_empty():
		var message := "PARDEX Online bağlantısı bekleniyor" if not PardexOnline.is_online() else "Henüz arkadaşın yok"
		_online_list.add_child(UI.empty_state("friends", message, "‘Arkadaş Ekle’ ile PARDEX kullanıcılarını bul.", true))
		return
	if shown.is_empty():
		_online_list.add_child(UI.empty_state("friends", "Şu an çevrimiçi arkadaşın yok", "", true))
		return
	for profile in shown:
		_online_list.add_child(_friend_row(profile))


func _friend_row(profile: Dictionary) -> Control:
	var account_id := str(profile.get("account_id", ""))
	var display_name := str(profile.get("display_name", "Pardus"))
	var presence := _presence(profile)
	var selected := account_id == _selected_id
	var holder := UI.panel(0, UI.box(Color(UI.ACCENT, 0.1) if selected else Color(UI.SURFACE_2, 0.55), 10, Color(UI.ACCENT, 0.5) if selected else UI.BORDER, 1, 8))
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	holder.gui_input.connect(func(event: InputEvent):
		var mouse := event as InputEventMouseButton
		if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_selected_id = account_id
			_render_online()
			_render_chat()
	)
	var row := UI.hbox(10)
	holder.add_child(row)
	row.add_child(UI.avatar(display_name, 42, presence))
	var text := UI.vbox(1)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.expand(text)
	var name_row := UI.hbox(8)
	name_row.add_child(UI.label(display_name, 14, UI.TEXT, true))
	var dot := UI.label("●", 11, UI.presence_color(presence))
	name_row.add_child(dot)
	name_row.add_child(UI.expand(UI.fit(UI.label(UI.presence_label(presence), 12, UI.presence_color(presence)))))
	text.add_child(name_row)
	text.add_child(UI.fit(UI.label(_activity(profile), 12, UI.TEXT_2)))
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
	var presence := _presence(profile)
	if bool(profile.get("room_joinable", false)) and not _friend_in_my_room(account_id):
		var join := UI.button("Katıl", "ghost", 12, 34, "gamepad")
		join.add_theme_stylebox_override("normal", UI.box(Color(UI.ACCENT_DARK, 0.55), 9, UI.ACCENT, 1))
		join.custom_minimum_size.x = 92
		join.pressed.connect(func(): PardexOnline.join_friend_room(account_id))
		return join
	if presence != "offline" and not _room().is_empty() and not _friend_in_my_room(account_id) and not bool(_room().get("launching", false)):
		var invite := UI.button("Davet Et", "ghost", 12, 34, "user_plus")
		invite.custom_minimum_size.x = 104
		invite.pressed.connect(func(): PardexOnline.send_room_invite(account_id))
		return invite
	if presence != "offline":
		var message := UI.button("Mesaj Gönder", "ghost", 12, 34)
		message.pressed.connect(func():
			_selected_id = account_id
			_render_online()
			_render_chat()
		)
		return message
	return null


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
		center.add_child(UI.avatar(str(profile.get("display_name", "P")), 56, "in_game", UI.ACCENT))
		cell.add_child(center)
		var name_label := UI.fit(UI.label(str(profile.get("display_name", "")), 13, UI.TEXT, true))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(name_label)
		var game_label := UI.fit(UI.label(str(profile.get("game_name", "")), 11, UI.TEXT_2))
		game_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(game_label)
		_playing_row.add_child(cell)


# ------------------------------------------------------------------ chat

func _build_chat() -> Control:
	_chat_panel = UI.panel(0)
	UI.expand(_chat_panel)
	_chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(0)
	_chat_panel.add_child(column)
	_chat_header = UI.hbox(12)
	column.add_child(UI.margin(_chat_header, 16, 14, 14, 14))
	column.add_child(UI.divider())
	_chat_body = UI.vbox(10)
	_chat_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body_margin := UI.margin(_chat_body, 18, 16, 18, 16)
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body_margin)
	var input_row := UI.hbox(10)
	column.add_child(UI.margin(input_row, 14, 0, 14, 14))
	var attach := UI.icon_button("plus", "Ek gönder (yakında)", 44, UI.TEXT_2, true)
	attach.disabled = true
	input_row.add_child(attach)
	var input := LineEdit.new()
	input.placeholder_text = "Bir mesaj yaz...  (mesajlaşma yakında)"
	input.editable = false
	input.custom_minimum_size.y = 44
	input.add_theme_font_size_override("font_size", 13)
	input.add_theme_color_override("font_placeholder_color", UI.TEXT_3)
	input.add_theme_stylebox_override("read_only", UI.box(Color(UI.SURFACE, 0.9), 10, UI.BORDER, 1, 12))
	UI.expand(input)
	input_row.add_child(input)
	var send := UI.icon_button("send", "Gönder (yakında)", 44, UI.TEXT, true)
	send.add_theme_stylebox_override("disabled", UI.box(Color(UI.ACCENT_DARK, 0.6), 10, UI.ACCENT_DARK, 1))
	send.disabled = true
	input_row.add_child(send)
	return _chat_panel


func _render_chat() -> void:
	UI.clear(_chat_header)
	UI.clear(_chat_body)
	var profile := _find_friend(_selected_id)
	if profile.is_empty():
		_chat_header.add_child(UI.label("Sohbet", 16, UI.TEXT, true))
		_chat_body.add_child(UI.empty_state("message", "Bir arkadaş seç", "Arkadaşların soldaki listede görünür."))
		return
	var display_name := str(profile.get("display_name", "Pardus"))
	var presence := _presence(profile)
	_chat_header.add_child(UI.avatar(display_name, 44, presence))
	var titles := UI.vbox(1)
	UI.expand(titles)
	titles.add_child(UI.fit(UI.label(display_name, 16, UI.TEXT, true)))
	var status := UI.hbox(6)
	status.add_child(UI.label("●", 11, UI.presence_color(presence)))
	status.add_child(UI.expand(UI.fit(UI.label("%s - %s" % [UI.presence_label(presence), _activity(profile)] if presence == "in_game" else UI.presence_label(presence), 12, UI.TEXT_2))))
	titles.add_child(status)
	_chat_header.add_child(titles)
	for spec in [["phone", "Sesli arama yakında"], ["video", "Görüntülü arama yakında"]]:
		var item := UI.icon_button(str(spec[0]), str(spec[1]), 40, UI.TEXT_2, true)
		item.disabled = true
		_chat_header.add_child(item)
	var more := UI.icon_button("dots", "Seçenekler", 40, UI.TEXT_2, true)
	more.pressed.connect(func(): _open_friend_menu(profile, more))
	_chat_header.add_child(more)

	_chat_body.add_child(UI.empty_state("message", "%s ile sohbet yakında" % display_name,
		"PARDEX mesajlaşması henüz hazır değil. Şimdilik birlikte oynamak için partine davet edebilir ya da onun partisine katılabilirsin."))
	var action := _row_action(profile)
	if action != null and action.text != "Mesaj Gönder":
		var holder := CenterContainer.new()
		holder.add_child(action)
		_chat_body.add_child(holder)
	_chat_body.add_child(UI.vspacer())


# ------------------------------------------------------------------ right column

func _build_right() -> Control:
	_right = UI.vbox(16)
	_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var party := UI.panel(16)
	_party = UI.vbox(12)
	party.add_child(_party)
	_right.add_child(party)

	var requests := UI.panel(16)
	var requests_column := UI.vbox(10)
	requests.add_child(requests_column)
	var header := UI.section_header("Bekleyen Davetler", "", 18)
	_requests_title = header.get_node("Title") as Label
	requests_column.add_child(header)
	_requests_list = UI.vbox(10)
	requests_column.add_child(_requests_list)
	_right.add_child(requests)

	var suggestions := UI.panel(16)
	suggestions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var suggestions_column := UI.vbox(10)
	suggestions.add_child(suggestions_column)
	suggestions_column.add_child(UI.section_header("Önerilen Arkadaşlar", "", 18))
	var line := UI.hbox(12)
	line.add_child(UI.icon_tile("user_plus", 44, UI.ACCENT))
	var copy := UI.vbox(2)
	UI.expand(copy)
	copy.add_child(UI.label("Öneriler yakında", 14, UI.TEXT, true))
	copy.add_child(UI.wrapped(UI.label("Şimdilik arkadaşlarını adıyla arayabilirsin.", 12, UI.TEXT_2)))
	line.add_child(copy)
	var find := UI.button("Ara", "ghost", 12, 34, "search")
	find.pressed.connect(_open_add_dialog)
	line.add_child(find)
	suggestions_column.add_child(line)
	_right.add_child(suggestions)
	return _right


func _render_party() -> void:
	UI.clear(_party)
	var room := _room()
	var in_room := not room.is_empty()
	var header := UI.hbox(10)
	header.add_child(UI.icon("users_group", 22, UI.PURPLE))
	header.add_child(UI.expand(UI.label("Parti" + (" • %s" % str(room.get("code", ""))) if in_room else "Parti Kur", 18, UI.TEXT, true)))
	var help := UI.icon_button("help", "Parti, arkadaşlarınla aynı oyuna girmek için kurduğun PARDEX Online odasıdır.", 30)
	header.add_child(help)
	_party.add_child(header)

	var members := _room_members()
	var slots := UI.hbox(12)
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	var ready_count := 0
	var self_ready := false
	for member in members:
		if typeof(member) != TYPE_DICTIONARY:
			continue
		var member_ready := bool(member.get("ready", false))
		ready_count += int(member_ready)
		if str(member.get("user_id", "")) == PardexOnline.user_id:
			self_ready = member_ready
		var avatar := UI.avatar(str(member.get("display_name", "P")), 60, "online" if member_ready else "away", UI.ACCENT)
		avatar.tooltip_text = "%s  •  %s" % [str(member.get("display_name", "")), "Hazır" if member_ready else "Bekliyor"]
		avatar.mouse_filter = Control.MOUSE_FILTER_PASS
		slots.add_child(avatar)
	var max_players := int(room.get("max_players", 4)) if in_room else 4
	for _slot in maxi(0, max_players - members.size()):
		var add := UI.icon_button("plus", "Arkadaş davet et", 60, UI.TEXT_2)
		add.add_theme_stylebox_override("normal", UI.box(Color.TRANSPARENT, 30, UI.BORDER_HI, 1))
		add.add_theme_stylebox_override("hover", UI.box(Color(1, 1, 1, 0.05), 30, UI.ACCENT, 1))
		add.pressed.connect(_open_invite_picker.bind(add))
		slots.add_child(add)
	_party.add_child(slots)

	var game := Catalog.game(str(room.get("game_id", "korsanlar")) if in_room else "korsanlar")
	var launching := bool(room.get("launching", false))
	var is_host := str(room.get("host_id", "")) == PardexOnline.user_id
	var all_ready := members.size() >= 2 and ready_count == members.size()
	var status_text := "%s  •  Arkadaşlarınla aynı odada oyna." % str(game.get("title", "PARDEX"))
	if in_room:
		status_text = "%s  •  %d/%d oyuncu hazır" % [str(game.get("title", "")), ready_count, max_players]
		if launching:
			status_text = "Oyun başlatılıyor…"
	var status := UI.fit(UI.label(status_text, 12, UI.GREEN if launching else UI.TEXT_2))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_party.add_child(status)

	var main_action: Button
	if not in_room:
		main_action = UI.button("Parti Kur", "primary", 15, 46, "friends")
		main_action.disabled = not PardexOnline.is_online()
		main_action.pressed.connect(_create_party)
	elif is_host and all_ready:
		main_action = UI.button("Oyunu Başlat", "gold", 15, 46, "play")
		main_action.disabled = launching or not str(room.get("game_server_url", "")).begins_with("ws")
		if main_action.disabled and not launching:
			main_action.tooltip_text = "Oyun sunucusu henüz atanmadı."
		main_action.pressed.connect(PardexOnline.request_start_game)
	else:
		main_action = UI.button("Hazır Değilim" if self_ready else "Hazırım", "success" if self_ready else "primary", 15, 46, "check")
		main_action.disabled = launching
		main_action.pressed.connect(func(): PardexOnline.set_ready(not self_ready))
		if is_host and not all_ready:
			main_action.tooltip_text = "En az 2 oyuncu hazır olduğunda oyunu başlatabilirsin."
	_party.add_child(main_action)

	var row := UI.hbox(10)
	if in_room:
		var share := UI.button("Kodu Paylaş", "ghost", 13, 42, "link")
		share.pressed.connect(func():
			DisplayServer.clipboard_set(str(room.get("code", "")))
			toast.emit("Parti kodu kopyalandı: %s" % str(room.get("code", "")))
		)
		row.add_child(UI.expand(share))
		var invite := UI.button("Davet Gönder", "ghost", 13, 42, "user_plus")
		invite.pressed.connect(_open_invite_picker.bind(invite))
		row.add_child(UI.expand(invite))
	else:
		var join := UI.button("Kodla Katıl", "ghost", 13, 42, "link")
		join.disabled = not PardexOnline.is_online()
		join.pressed.connect(func():
			_code_edit.text = ""
			_code_dialog.popup_centered()
			_code_edit.grab_focus()
		)
		row.add_child(UI.expand(join))
		var voice := UI.button("Sesli Oda", "ghost", 13, 42, "headphones")
		voice.disabled = true
		voice.tooltip_text = "Sesli sohbet yakında."
		row.add_child(UI.expand(voice))
	_party.add_child(row)
	if in_room:
		var leave := UI.button("Partiden Ayrıl", "link", 12, 26, "log_out")
		leave.add_theme_color_override("font_color", UI.RED)
		leave.add_theme_color_override("font_hover_color", UI.RED.lightened(0.2))
		leave.add_theme_color_override("icon_normal_color", UI.RED)
		leave.pressed.connect(PardexOnline.leave_room)
		_party.add_child(leave)


func _create_party() -> void:
	if not PardexOnline.is_online():
		toast.emit("Parti kurmak için PARDEX Online bağlantısı gerekli.")
		return
	if not _room().is_empty():
		toast.emit("Zaten bir partidesin.")
		return
	PardexOnline.create_room("korsanlar", 4)


func _open_invite_picker(anchor: Control) -> void:
	if _room().is_empty():
		_create_party()
		return
	_invite_picker.clear()
	for profile in _friends():
		if typeof(profile) != TYPE_DICTIONARY or _presence(profile) == "offline":
			continue
		var account_id := str(profile.get("account_id", ""))
		if _friend_in_my_room(account_id):
			continue
		_invite_picker.add_item(str(profile.get("display_name", "Pardus")))
		_invite_picker.set_item_metadata(_invite_picker.item_count - 1, account_id)
	if _invite_picker.item_count == 0:
		toast.emit("Davet edilebilecek çevrimiçi arkadaşın yok.")
		return
	var rect := anchor.get_global_rect()
	_invite_picker.popup(Rect2i(Vector2i(rect.position + Vector2(0, rect.size.y + 4)), Vector2i.ZERO))


func _render_requests() -> void:
	UI.clear(_requests_list)
	var incoming := _requests("incoming_requests")
	_requests_title.text = "Bekleyen Davetler (%d)" % incoming.size()
	if incoming.is_empty():
		_requests_list.add_child(UI.empty_state("mail", "Bekleyen arkadaşlık isteği yok", "", true))
		return
	for profile in incoming.slice(0, 3):
		if typeof(profile) != TYPE_DICTIONARY:
			continue
		var account_id := str(profile.get("account_id", ""))
		var row := UI.hbox(10)
		row.add_child(UI.avatar(str(profile.get("display_name", "P")), 44, _presence(profile)))
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
	_friend_menu.add_item("Partime davet et", 0)
	_friend_menu.set_item_disabled(0, _room().is_empty() or _presence(profile) == "offline" or _friend_in_my_room(_menu_account_id))
	_friend_menu.add_item("Partisine katıl", 1)
	_friend_menu.set_item_disabled(1, not bool(profile.get("room_joinable", false)))
	_friend_menu.add_separator()
	_friend_menu.add_item("Arkadaşlıktan çıkar", 2)
	var rect := anchor.get_global_rect()
	_friend_menu.popup(Rect2i(Vector2i(rect.position + Vector2(0, rect.size.y)), Vector2i.ZERO))


func _build_add_dialog() -> void:
	_add_dialog = AcceptDialog.new()
	_add_dialog.title = "Arkadaş Ekle"
	_add_dialog.ok_button_text = "Kapat"
	_add_dialog.min_size = Vector2i(480, 440)
	add_child(_add_dialog)
	var column := UI.vbox(10)
	_add_dialog.add_child(column)
	var search_row := UI.hbox(8)
	column.add_child(search_row)
	var field := UI.search_field("Kullanıcı adı veya PARDEX kimliği...", 40)
	UI.expand(field)
	search_row.add_child(field)
	var go := UI.button("Ara", "primary", 13, 40)
	search_row.add_child(go)
	go.pressed.connect(func(): _search_users(field.text))
	field.text_submitted.connect(_search_users)
	_add_hint = UI.label("PARDEX kullanıcılarını adıyla bul.", 12, UI.TEXT_3)
	column.add_child(_add_hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 280
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_add_results = UI.vbox(8)
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
		var row := UI.hbox(10)
		row.add_child(UI.avatar(str(profile.get("display_name", "P")), 36, _presence(profile)))
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
		_add_results.add_child(row)


func _build_code_dialog() -> void:
	_code_dialog = ConfirmationDialog.new()
	_code_dialog.title = "Kodla Partiye Katıl"
	_code_dialog.ok_button_text = "Katıl"
	_code_dialog.cancel_button_text = "Vazgeç"
	_code_dialog.min_size = Vector2i(380, 150)
	add_child(_code_dialog)
	var column := UI.vbox(8)
	_code_dialog.add_child(column)
	column.add_child(UI.label("Arkadaşının paylaştığı 5 karakterlik parti kodunu gir.", 13, UI.TEXT_2))
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Örn. K7P2Q"
	_code_edit.max_length = 5
	_code_edit.custom_minimum_size.y = 40
	column.add_child(_code_edit)
	var submit := func():
		var code := _code_edit.text.strip_edges().to_upper()
		if code.length() == 5:
			PardexOnline.join_room(code)
			_code_dialog.hide()
		else:
			toast.emit("Parti kodu 5 karakter olmalı.")
	_code_dialog.confirmed.connect(submit)
	_code_edit.text_submitted.connect(func(_text: String): submit.call())


func _on_connection_state_changed(state: String) -> void:
	if state == "online":
		PardexOnline.request_social_state()
	_render()


func _build_invite_dialog() -> void:
	_invite_dialog = ConfirmationDialog.new()
	_invite_dialog.title = "PARDEX Parti Daveti"
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
	_invite_dialog.dialog_text = "%s seni %s partisine davet ediyor.\n\nParti kodu: %s   •   Oyuncular: %d / %d" % [
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
		toast.emit("Parti davetinin süresi doldu.")
	elif was_visible and reason in ["room_closed", "room_full", "room_in_game"]:
		toast.emit("Davet edilen parti artık katılıma uygun değil.")
