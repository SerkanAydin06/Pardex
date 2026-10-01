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
const HERO_HEIGHT := 300.0

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
	add_theme_constant_override("separation", 0)
	_columns = BoxContainer.new()
	_columns.add_theme_constant_override("separation", 16)
	add_child(UI.scroll_page(_columns))

	var main := UI.vbox(14)
	UI.expand(main, 2.4)
	_columns.add_child(main)
	main.add_child(_build_banner())
	_stats_row = UI.hbox(12)
	main.add_child(_stats_row)
	main.add_child(_build_badges())
	main.add_child(_build_achievements())
	main.add_child(_build_favorites())

	_right = UI.vbox(16)
	UI.expand(_right, 1.0)
	_columns.add_child(_right)
	_right.add_child(_build_account())
	_right.add_child(_build_events())

	PardexOnline.presence_changed.connect(func(_p): _render_identity())
	PardexOnline.connection_state_changed.connect(func(_s): refresh())
	PardexOnline.social_state_changed.connect(func(_s): refresh())
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh())
	refresh()


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
	_right.custom_minimum_size.x = 0.0 if _columns.vertical else clampf(content_width * 0.28, 320.0, 420.0)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _columns.vertical else Control.SIZE_FILL


# ------------------------------------------------------------------ banner

func _build_banner() -> Control:
	var frame := UI.image(Catalog.texture("res://assets/ui/top_banner.png"), Vector2(0, HERO_HEIGHT), 16)
	frame.add_theme_stylebox_override("panel", UI.glow_style(0, 16))
	frame.add_child(UI.shade(0.92, true))
	var row := UI.hbox(24)
	frame.add_child(UI.margin(row, 30, 20, 24, 20))
	_avatar_slot = CenterContainer.new()
	row.add_child(_avatar_slot)
	var text := UI.vbox(10)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.expand(text)
	row.add_child(text)
	_name_label = UI.label("", 42, UI.TEXT, true)
	text.add_child(_name_label)
	var level_row := UI.hbox(12)
	level_row.add_child(UI.pill("Seviye yakında", UI.ACCENT, "", 13, true))
	var bar := UI.progress(0.0, UI.ACCENT, 6)
	bar.custom_minimum_size.x = 200
	level_row.add_child(bar)
	level_row.add_child(UI.label("0 XP", 12, UI.TEXT_2))
	text.add_child(level_row)
	text.add_child(UI.label("“Oyunlar daha güzel, birlikte oynayınca.”", 16, UI.TEXT))
	var bottom := UI.hbox(14)
	_status_row = UI.hbox(8)
	bottom.add_child(_status_row)
	bottom.add_child(UI.spacer())
	var edit := UI.button("Profili Düzenle", "ghost", 15, 48, "pencil")
	edit.custom_minimum_size.x = 200
	edit.add_theme_stylebox_override("normal", UI.box(Color(UI.BG, 0.75), 10, UI.BORDER_HI, 1))
	edit.pressed.connect(func(): navigate.emit("settings"))
	bottom.add_child(edit)
	text.add_child(bottom)
	return frame


func _render_identity() -> void:
	_name_label.text = display_name
	var presence := PardexOnline.effective_presence if PardexOnline.is_online() else "offline"
	UI.clear(_avatar_slot)
	var avatar := UI.avatar(display_name, 176, presence, UI.ACCENT)
	_avatar_slot.add_child(avatar)
	UI.clear(_status_row)
	_status_row.add_child(UI.label("●", 16, UI.presence_color(presence)))
	_status_row.add_child(UI.label(UI.presence_label(presence), 16, UI.presence_color(presence)))


func _render_stats() -> void:
	UI.clear(_stats_row)
	var friends = PardexOnline.social_state.get("friends", [])
	for stat in [
		["gamepad", str(Catalog.GAMES.size()), "Oyun Sayısı", UI.ACCENT],
		["trophy", "0", "Başarım", UI.GOLD],
		["clock", Catalog.hours(Catalog.total_playtime()), "Toplam Oynama Süresi", UI.ACCENT],
		["friends", str((friends as Array).size() if typeof(friends) == TYPE_ARRAY else 0), "Arkadaş Sayısı", UI.ACCENT],
	]:
		_stats_row.add_child(UI.expand(UI.stat_tile(str(stat[0]), str(stat[1]), str(stat[2]), stat[3])))


# ------------------------------------------------------------------ badges + achievements

func _build_badges() -> Control:
	var card := UI.panel(16)
	var column := UI.vbox(12)
	card.add_child(column)
	var header := UI.section_header("Rozetler", "Tüm Rozetleri Gör", 20)
	(header.get_node("Link") as Button).visible = false
	column.add_child(header)
	var row := UI.hbox(10)
	for _index in 6:
		var cell := UI.vbox(6)
		UI.expand(cell)
		var badge := CenterContainer.new()
		var hex := UI.icon("hex", 62, Color(UI.TEXT_3, 0.7))
		badge.add_child(hex)
		var lock := UI.icon("lock", 22, UI.TEXT_2)
		hex.add_child(lock)
		lock.position = Vector2(20, 20)
		cell.add_child(badge)
		var name_label := UI.label("Gizli Rozet", 13, UI.TEXT_2, true)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(name_label)
		var hint := UI.label("???", 11, UI.TEXT_3)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(hint)
		row.add_child(cell)
	column.add_child(row)
	return card


func _build_achievements() -> Control:
	var card := UI.panel(16)
	var column := UI.vbox(12)
	card.add_child(column)
	column.add_child(UI.section_header("Son Başarımlar", "", 20))
	var line := UI.hbox(14)
	line.add_child(UI.icon_tile("trophy", 52, UI.GOLD))
	var copy := UI.vbox(4)
	UI.expand(copy)
	copy.add_child(UI.label("Başarım sistemi yakında", 15, UI.TEXT, true))
	copy.add_child(UI.wrapped(UI.label("PARDEX oyunlarındaki başarımların burada listelenecek.", 12, UI.TEXT_2)))
	copy.add_child(UI.progress(0.0, UI.GREEN, 5))
	line.add_child(copy)
	column.add_child(line)
	return card


func _build_favorites() -> Control:
	var card := UI.panel(16)
	var column := UI.vbox(12)
	card.add_child(column)
	var header := UI.section_header("Favori Oyunlar", "Tümünü Gör", 20)
	(header.get_node("Link") as Button).pressed.connect(func(): navigate.emit("library"))
	column.add_child(header)
	_favorites_row = UI.hbox(12)
	column.add_child(_favorites_row)
	return card


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

func _build_account() -> Control:
	var card := UI.panel(18)
	var column := UI.vbox(10)
	card.add_child(column)
	var header := UI.hbox(8)
	header.add_child(UI.expand(UI.label("Hesap Bilgileri", 22, UI.TEXT, true)))
	var gear := UI.icon_button("gear", "Ayarlar", 34, UI.ACCENT)
	gear.pressed.connect(func(): navigate.emit("settings"))
	header.add_child(gear)
	column.add_child(header)
	_account_list = UI.vbox(0)
	column.add_child(_account_list)
	return card


func _account_row(icon_name: String, title: String, detail: String, trailing: Control = null, title_color := UI.TEXT) -> Control:
	var row := UI.hbox(14)
	row.add_child(UI.icon_tile(icon_name, 50, UI.ACCENT if icon_name != "crown" else UI.GOLD))
	var text := UI.vbox(2)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.expand(text)
	var title_row := UI.hbox(8)
	title_row.add_child(UI.expand(UI.fit(UI.label(title, 16, title_color, false))))
	text.add_child(title_row)
	if not detail.is_empty():
		text.add_child(UI.fit(UI.label(detail, 12, UI.TEXT_2)))
	row.add_child(text)
	if trailing != null:
		row.add_child(trailing)
	return UI.margin(row, 0, 8, 0, 8)


func _render_account() -> void:
	UI.clear(_account_list)
	var account_id := PardexOnline.account_id
	_account_list.add_child(_account_row("mail", account_id if not account_id.is_empty() else "PARDEX kimliği bekleniyor", "PARDEX hesap kimliğin"))
	_account_list.add_child(UI.divider())
	_account_list.add_child(_account_row("calendar", Catalog.date_text(Catalog.joined_at()), "PARDEX'e katıldı"))
	_account_list.add_child(UI.divider())
	var recovery := UI.link("Kod oluştur", 12)
	recovery.pressed.connect(func(): navigate.emit("settings"))
	_account_list.add_child(_account_row("shield", "Hesap Kurtarma", "Kurtarma koduyla hesabını başka bilgisayara taşı", recovery))
	_account_list.add_child(UI.divider())
	var plus_row := _account_row("crown", "PARDEX Plus", "Daha fazla ayrıcalık yakında!", UI.pill("Yakında", UI.GOLD, "", 11), UI.GOLD)
	_account_list.add_child(plus_row)


func _build_events() -> Control:
	var card := UI.panel(18)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := UI.vbox(12)
	card.add_child(column)
	column.add_child(UI.section_header("Son Etkinlikler", "", 22))
	_events_list = UI.vbox(12)
	column.add_child(_events_list)
	return card


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
