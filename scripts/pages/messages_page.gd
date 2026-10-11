extends VBoxContainer

# Mesajlar: one-to-one chat with friends. Left: conversations (friends, most
# recent first, unread badges). Right: the open conversation and a message
# box. History lives on the server (last 200 messages per friend).

signal navigate(page: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const ConversationRowScene := preload("res://scenes/ui/conversation_row.tscn")
const BUBBLE_MAX_WIDTH := 520.0
const ChatBubbleScene := preload("res://scenes/ui/chat_bubble.tscn")

var _selected_id := ""
var _filter := ""
var _histories: Dictionary = {}
var _list: VBoxContainer
var _search: LineEdit
var _left: Control
var _header: HBoxContainer
var _messages: VBoxContainer
var _scroll: ScrollContainer
var _input: LineEdit
var _send: Button
var _bubble_max_width := BUBBLE_MAX_WIDTH


func _ready() -> void:
	# The layout lives in scenes/pages/messages_page.tscn; building from code
	# only happens when the script runs without its scene.
	if get_child_count() == 0:
		_build()
		UI.own(self)
	_bind()
	PardexOnline.social_state_changed.connect(func(_state):
		# Friends arrive after the page is built: pick a conversation then.
		if _selected_id.is_empty() or _find_friend(_selected_id).is_empty():
			_render()
			return
		_render_list()
		_render_header()
		_mark_read()
	)
	PardexOnline.avatar_ready.connect(func(_account_id): _render_list(); _render_header())
	PardexOnline.connection_state_changed.connect(func(_state): _render())
	PardexOnline.welcome_received.connect(func(_user_id, _display_name):
		# Messages delivered while disconnected must be fetched from the server.
		_histories.clear()
		_render()
	)
	PardexOnline.chat_history_received.connect(_on_history)
	PardexOnline.chat_message_received.connect(_on_message)
	visibility_changed.connect(func():
		if visible:
			_render()
	)
	_render()


func _bind() -> void:
	_list = %ConversationList
	_search = %ConversationSearch
	_left = %ConversationColumn
	_header = %ChatHeader
	_messages = %MessageList
	_scroll = %MessageScroll
	_input = %MessageInput
	_send = %SendButton
	_search.text_changed.connect(func(text: String):
		_filter = text.strip_edges().to_lower()
		_render_list()
	)
	_send.pressed.connect(_send_current)
	_input.text_submitted.connect(func(_text: String): _send_current())


func _build() -> void:
	add_theme_constant_override("separation", 12)
	var heading := UI.vbox(3)
	var title := UI.hbox(12)
	title.add_child(UI.icon("message", 26, UI.ACCENT))
	title.add_child(UI.label("Mesajlar", 30, UI.TEXT, true))
	heading.add_child(title)
	heading.add_child(UI.label("Arkadaşlarınla doğrudan yazış, oyundaysa tek tıkla katıl.", 13, UI.TEXT_2))
	add_child(heading)
	var columns := UI.named(UI.hbox(16), "MessageColumns") as HBoxContainer
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(columns)

	var left := UI.named(UI.panel(14), "ConversationColumn") as PanelContainer
	left.custom_minimum_size.x = 340
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left_column := UI.vbox(10)
	left.add_child(left_column)
	left_column.add_child(UI.named(UI.search_field("Sohbetlerde ara...", 38), "ConversationSearch"))
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UI.named(UI.vbox(6), "ConversationList") as VBoxContainer
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list)
	left_column.add_child(list_scroll)
	columns.add_child(left)

	var chat := UI.named(UI.panel(0), "ChatPanel") as PanelContainer
	UI.expand(chat)
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var chat_column := UI.vbox(0)
	chat.add_child(chat_column)
	chat_column.add_child(UI.margin(UI.named(UI.hbox(12), "ChatHeader"), 18, 14, 18, 14))
	chat_column.add_child(UI.divider())
	var scroll := UI.named(ScrollContainer.new(), "MessageScroll") as ScrollContainer
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var messages := UI.named(UI.vbox(8), "MessageList") as VBoxContainer
	messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var messages_margin := UI.margin(messages, 20, 16, 20, 16)
	messages_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(messages_margin)
	chat_column.add_child(scroll)
	chat_column.add_child(UI.divider())
	var input_row := UI.hbox(10)
	chat_column.add_child(UI.margin(input_row, 16, 12, 16, 14))
	var input := UI.named(LineEdit.new(), "MessageInput") as LineEdit
	input.placeholder_text = "Bir mesaj yaz..."
	input.max_length = 500
	input.custom_minimum_size.y = 46
	input.add_theme_font_size_override("font_size", 14)
	input.add_theme_color_override("font_placeholder_color", UI.TEXT_3)
	input.add_theme_stylebox_override("normal", UI.box(Color(UI.SURFACE, 0.9), 10, UI.BORDER, 1, 12))
	input.add_theme_stylebox_override("focus", UI.box(Color(UI.SURFACE, 0.9), 10, UI.ACCENT, 1, 12))
	UI.expand(input)
	input_row.add_child(input)
	var send := UI.button("Gönder", "primary", 14, 46, "send")
	send.custom_minimum_size.x = 130
	input_row.add_child(UI.named(send, "SendButton"))
	columns.add_child(chat)


func apply_layout(content_width: float) -> void:
	var left_width := clampf(content_width * 0.3, 280.0, 400.0)
	_left.custom_minimum_size.x = left_width
	# Keep long bubbles inside the chat panel on the 1024 px minimum window.
	# 16 = column gap; the rest reserves the message margins + bubble padding.
	_bubble_max_width = clampf(content_width - left_width - 16.0 - 100.0, 180.0, BUBBLE_MAX_WIDTH)


# ------------------------------------------------------------------ data

func open_conversation(account_id: String) -> void:
	_selected_id = account_id
	_render()
	_input.grab_focus()


func _friends() -> Array:
	var value = PardexOnline.social_state.get("friends", [])
	return value if typeof(value) == TYPE_ARRAY else []


func _find_friend(account_id: String) -> Dictionary:
	for profile in _friends():
		if typeof(profile) == TYPE_DICTIONARY and str(profile.get("account_id", "")) == account_id:
			return profile
	return {}


func _presence(profile: Dictionary) -> String:
	return str(profile.get("presence", "online" if bool(profile.get("online", false)) else "offline"))


func _picture(profile: Dictionary) -> Texture2D:
	return PardexOnline.avatar_texture(str(profile.get("account_id", "")), str(profile.get("avatar_id", "")))


# Most recent conversation first; friends never written to follow, online first.
func _sorted_friends() -> Array:
	var friends := _friends().filter(func(p): return typeof(p) == TYPE_DICTIONARY)
	friends.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var at_a := int(a.get("chat_last_at", 0))
		var at_b := int(b.get("chat_last_at", 0))
		if at_a != at_b:
			return at_a > at_b
		var online_a := _presence(a) != "offline"
		var online_b := _presence(b) != "offline"
		if online_a != online_b:
			return online_a
		return str(a.get("display_name", "")).naturalnocasecmp_to(str(b.get("display_name", ""))) < 0
	)
	return friends


static func _clock(at_ms: int) -> String:
	if at_ms <= 0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var local := floori(at_ms / 1000.0) + bias
	var now := int(Time.get_unix_time_from_system()) + bias
	var stamp := Time.get_datetime_dict_from_unix_time(local)
	if floori(local / 86400.0) == floori(now / 86400.0):
		return "%02d:%02d" % [stamp["hour"], stamp["minute"]]
	return "%02d.%02d %02d:%02d" % [stamp["day"], stamp["month"], stamp["hour"], stamp["minute"]]


# ------------------------------------------------------------------ render

func _render() -> void:
	if _selected_id.is_empty() or _find_friend(_selected_id).is_empty():
		var friends := _sorted_friends()
		_selected_id = str(friends[0].get("account_id", "")) if not friends.is_empty() else ""
	_render_list()
	_render_header()
	_render_messages()
	if not _selected_id.is_empty() and not _histories.has(_selected_id):
		PardexOnline.request_chat_history(_selected_id)
	_mark_read()


func _render_list() -> void:
	UI.clear(_list)
	var friends := _sorted_friends()
	if friends.is_empty():
		var message := "PARDEX Online bağlantısı bekleniyor" if not PardexOnline.is_online() else "Henüz arkadaşın yok"
		var state := UI.empty_state("friends", message, "Arkadaşlar sekmesinden yeni kişiler ekleyebilirsin.", true)
		var action := UI.button("Arkadaşlara Git", "ghost", 12, 34, "user_plus")
		action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		action.pressed.connect(func(): navigate.emit("friends"))
		state.add_child(action)
		_list.add_child(state)
		return
	var shown := 0
	for profile in friends:
		var friend_name := str(profile.get("display_name", "Pardus"))
		if not _filter.is_empty() and not friend_name.to_lower().contains(_filter):
			continue
		_list.add_child(_conversation_row(profile))
		shown += 1
	if shown == 0:
		_list.add_child(UI.empty_state("search", "Eşleşen arkadaş yok", "", true))


# Editable conversation-row layout (scenes/ui/conversation_row.tscn).
func _conversation_row(profile: Dictionary) -> Control:
	var account_id := str(profile.get("account_id", ""))
	var friend_name := str(profile.get("display_name", "Pardus"))
	var presence := _presence(profile)
	var selected := account_id == _selected_id
	var unread := int(profile.get("chat_unread", 0))
	var holder := ConversationRowScene.instantiate() as PanelContainer
	holder.add_theme_stylebox_override("panel", UI.box(Color(UI.ACCENT, 0.12) if selected else Color(UI.SURFACE_2, 0.5), 10, Color(UI.ACCENT, 0.55) if selected else UI.BORDER, 1, 10))
	holder.gui_input.connect(func(event: InputEvent):
		var mouse := event as InputEventMouseButton
		if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			open_conversation(account_id)
	)
	(holder.get_node("Row/AvatarSlot") as HBoxContainer).add_child(UI.avatar(friend_name, 44, presence, Color.TRANSPARENT, _picture(profile)))
	(holder.get_node("Row/Info/Top/Name") as Label).text = friend_name
	var when := _clock(int(profile.get("chat_last_at", 0)))
	var time := holder.get_node("Row/Info/Top/When") as Label
	time.text = when
	time.visible = not when.is_empty()
	var preview := str(profile.get("chat_last_text", ""))
	if preview.is_empty():
		preview = UI.presence_label(presence)
	elif bool(profile.get("chat_last_mine", false)):
		preview = "Sen: " + preview
	var preview_label := holder.get_node("Row/Info/Bottom/Preview") as Label
	preview_label.text = preview.replace("\n", " ")
	preview_label.add_theme_color_override("font_color", UI.TEXT if unread > 0 else UI.TEXT_2)
	if unread > 0:
		preview_label.add_theme_font_override("font", UI._get_bold_font())
	var badge := holder.get_node("Row/Info/Bottom/UnreadBadge") as PanelContainer
	badge.visible = unread > 0
	(badge.get_node("Count") as Label).text = str(mini(unread, 99))
	return holder


func _render_header() -> void:
	UI.clear(_header)
	var profile := _find_friend(_selected_id)
	var can_write := not profile.is_empty() and PardexOnline.is_online()
	_input.editable = can_write
	_send.disabled = not can_write
	_input.placeholder_text = "Bir mesaj yaz..." if can_write else "Mesajlaşmak için bir arkadaş seç"
	if profile.is_empty():
		_header.add_child(UI.label("Sohbet", 18, UI.TEXT, true))
		return
	var friend_name := str(profile.get("display_name", "Pardus"))
	var presence := _presence(profile)
	_header.add_child(UI.avatar(friend_name, 46, presence, Color.TRANSPARENT, _picture(profile)))
	var titles := UI.vbox(2)
	UI.expand(titles)
	titles.add_child(UI.fit(UI.label(friend_name, 17, UI.TEXT, true)))
	var status := UI.presence_label(presence)
	var game_name := str(profile.get("game_name", ""))
	if presence == "in_game" and not game_name.is_empty():
		status += " • " + game_name
	titles.add_child(UI.fit(UI.label("●  " + status, 12, UI.presence_color(presence) if presence != "offline" else UI.TEXT_3)))
	_header.add_child(titles)
	# A friend at an open table can be joined straight from the chat.
	if bool(profile.get("room_joinable", false)):
		var join := UI.button("Katıl", "primary", 13, 38, "gamepad")
		join.custom_minimum_size.x = 120
		join.pressed.connect(func(): PardexOnline.join_friend_room(_selected_id))
		_header.add_child(join)


func _render_messages() -> void:
	UI.clear(_messages)
	var profile := _find_friend(_selected_id)
	if profile.is_empty():
		var state := UI.empty_state("message", "Konuşmaya başla", "Bir arkadaş seç veya Arkadaşlar sekmesinden yeni birini ekle.")
		var action := UI.button("Arkadaşlara Git", "ghost", 13, 40, "friends")
		action.custom_minimum_size.x = 150
		action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		action.pressed.connect(func(): navigate.emit("friends"))
		state.add_child(action)
		_messages.add_child(state)
		return
	if not _histories.has(_selected_id):
		_messages.add_child(UI.empty_state("message", "Mesajlar yükleniyor…", "", true))
		return
	var history: Array = _histories[_selected_id]
	if history.is_empty():
		_messages.add_child(UI.empty_state("message", "%s ile henüz mesajın yok" % str(profile.get("display_name", "")), "İlk mesajı sen yaz."))
		return
	for message in history:
		_messages.add_child(_bubble(message))
	_scroll_to_bottom()


func _bubble(message: Dictionary) -> Control:
	var mine := str(message.get("from", "")) == PardexOnline.account_id
	var row := ChatBubbleScene.instantiate() as HBoxContainer
	(row.get_node("LeftSpacer") as Control).visible = mine
	(row.get_node("RightSpacer") as Control).visible = not mine
	var bubble := row.get_node("Bubble") as PanelContainer
	if mine:
		bubble.add_theme_stylebox_override("panel", UI.box(Color(UI.ACCENT_DARK, 0.85), 12, Color(UI.ACCENT, 0.45), 1, 12))
	var content := row.get_node("Bubble/Column/MessageText") as Label
	content.text = str(message.get("text", ""))
	var font := content.get_theme_font("font")
	var width := font.get_multiline_string_size(content.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x if font != null else BUBBLE_MAX_WIDTH
	content.custom_minimum_size.x = clampf(width + 2.0, 40.0, _bubble_max_width)
	(row.get_node("Bubble/Column/MessageTime") as Label).text = _clock(int(message.get("at", 0)))
	return row


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


# ------------------------------------------------------------------ actions

func _send_current() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty() or _selected_id.is_empty():
		return
	if not PardexOnline.send_chat(_selected_id, text).is_empty():
		_input.clear()


func _mark_read() -> void:
	if visible and not _selected_id.is_empty() and int(_find_friend(_selected_id).get("chat_unread", 0)) > 0:
		PardexOnline.mark_chat_read(_selected_id)


func _on_history(with_account_id: String, messages: Array) -> void:
	_histories[with_account_id] = messages.duplicate(true)
	if with_account_id == _selected_id:
		_render_messages()


func _on_message(with_account_id: String, message: Dictionary, _client_id: String) -> void:
	if _histories.has(with_account_id):
		(_histories[with_account_id] as Array).append(message)
	if with_account_id == _selected_id:
		_render_messages()
		_mark_read()
