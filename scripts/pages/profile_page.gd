extends VBoxContainer

# Profil: banner with identity, headline stats, badges, recent achievements,
# favorite games, account information and recent activity.
# Name, presence, PARDEX ID and friends come from PARDEX Online; games,
# playtime, favorites, join date and activity from the local records. Levels,
# badges, achievements and PARDEX Plus have no backend yet and show their
# locked / "yakında" state.

signal navigate(page: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")

var display_name := "Pardus"

var _columns: BoxContainer
var _avatar_slot: CenterContainer
var _name_label: Label
var _status_row: HBoxContainer
var _stats_row: HBoxContainer
var _favorites_row: HBoxContainer
var _account_list: VBoxContainer
var _events_list: VBoxContainer
var _right: VBoxContainer


func _ready() -> void:
	# Layout is owned by scenes/pages; runtime code only binds data and actions.
	_bind()
	PardexOnline.presence_changed.connect(func(_p): _render_identity())
	PardexOnline.avatar_ready.connect(func(_id): _render_identity())
	PardexOnline.connection_state_changed.connect(func(_s): refresh())
	PardexOnline.social_state_changed.connect(func(_s): refresh())
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh())
	refresh()


func _bind() -> void:
	_columns = %Columns
	_avatar_slot = %AvatarSlot
	_name_label = %NameLabel
	_status_row = %StatusRow
	_stats_row = %StatsRow
	_favorites_row = %FavoritesRow
	_account_list = %AccountList
	_events_list = %EventsList
	_right = %RightColumn
	(%EditProfileButton as Button).pressed.connect(func(): navigate.emit("settings"))
	(%FavoritesLink as Button).pressed.connect(func(): navigate.emit("library"))
	(%AccountSettingsButton as Button).pressed.connect(func(): navigate.emit("settings"))
	(_account_list.get_node("RecoveryRow/Row/RecoveryLink") as Button).pressed.connect(func(): navigate.emit("settings"))


func refresh() -> void:
	if _name_label == null:
		return
	_render_identity()
	_render_stats()
	_render_favorites()
	_render_account()
	_render_events()


func apply_layout(content_width: float) -> void:
	_columns.vertical = content_width < 1000.0
	_right.custom_minimum_size.x = 0.0 if _columns.vertical else clampf(content_width * 0.3, 340.0, 420.0)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _columns.vertical else Control.SIZE_FILL


# ------------------------------------------------------------------ banner

func _render_identity() -> void:
	_name_label.text = display_name
	var presence := PardexOnline.effective_presence if PardexOnline.is_online() else "offline"
	UI.clear(_avatar_slot)
	var avatar := UI.avatar(display_name, 156, presence, UI.ACCENT, PardexOnline.my_avatar_texture())
	# Click the picture to change it (Ayarlar → Profil resmi).
	avatar.mouse_filter = Control.MOUSE_FILTER_STOP
	avatar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	avatar.tooltip_text = "Profil resmini değiştir"
	avatar.gui_input.connect(func(event: InputEvent):
		var mouse := event as InputEventMouseButton
		if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			navigate.emit("settings")
	)
	_avatar_slot.add_child(avatar)
	UI.clear(_status_row)
	var status_color := UI.presence_color(presence) if presence != "offline" else UI.TEXT_2
	_status_row.add_child(UI.pill(UI.presence_label(presence), status_color, "", 13))


func _render_stats() -> void:
	var friends = PardexOnline.social_state.get("friends", [])
	for stat in [
		["GamesStat", str(Catalog.all_games().size())],
		["AchievementsStat", "0"],
		["PlaytimeStat", Catalog.hours(Catalog.total_playtime())],
		["FriendsStat", str((friends as Array).size() if typeof(friends) == TYPE_ARRAY else 0)],
	]:
		(_stats_row.get_node("%s/Row/Text/Value" % stat[0]) as Label).text = str(stat[1])


# ------------------------------------------------------------------ badges + achievements

func _render_favorites() -> void:
	UI.clear(_favorites_row)
	var games := Catalog.games_with_stats().filter(func(g): return g["favorite"])
	if games.is_empty():
		_favorites_row.add_child(UI.expand(UI.empty_state("star", "Henüz favori oyunun yok", "Kütüphanedeki ☆ ile favori ekleyebilirsin.", true)))
		return
	for entry in games.slice(0, 5):
		var art := UI.image(Catalog.texture(str(entry["cover"])), Vector2(0, 110), 10)
		UI.expand(art)
		art.add_child(UI.shade(0.95))
		var text := UI.vbox(1)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(UI.vspacer())
		text.add_child(UI.fit(UI.label(str(entry["title"]), 14, UI.TEXT, true)))
		var time_row := UI.hbox(5)
		time_row.add_child(UI.icon("clock", 12, UI.TEXT_2))
		time_row.add_child(UI.label(Catalog.hours(int(entry["playtime"])), 12, UI.TEXT_2))
		text.add_child(time_row)
		art.add_child(UI.margin(text, 10, 8, 10, 8))
		_favorites_row.add_child(art)


# ------------------------------------------------------------------ right column

func _render_account() -> void:
	var account_id := PardexOnline.account_id
	var tag := ("#" + account_id.right(6).to_upper()) if not account_id.is_empty() else "Sunucuya bağlanınca oluşur"
	(_account_list.get_node("IdentityRow/Row/Text/Detail") as Label).text = tag
	(_account_list.get_node("JoinedRow/Row/Text/TitleRow/Title") as Label).text = Catalog.date_text(Catalog.joined_at())


func _render_events() -> void:
	UI.clear(_events_list)
	var events := Catalog.events()
	if events.is_empty():
		_events_list.add_child(UI.empty_state("clock", "Henüz etkinlik yok", "Oyun oynadıkça etkinliklerin burada görünür.", true))
		return
	for event in events.slice(0, 5):
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var row := UI.hbox(14)
		var game := Catalog.game(str(event.get("game", "")))
		if not game.is_empty():
			row.add_child(UI.image(Catalog.texture(str(game["cover"])), Vector2(58, 58), 10))
		else:
			row.add_child(UI.icon_tile("trophy", 58, UI.GOLD))
		var text := UI.vbox(2)
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		UI.expand(text)
		text.add_child(UI.wrapped(UI.label(str(event.get("text", "")), 15, UI.TEXT)))
		text.add_child(UI.label(Catalog.ago(int(event.get("at", 0))), 12, UI.TEXT_2))
		row.add_child(text)
		_events_list.add_child(row)
