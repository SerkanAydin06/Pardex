extends VBoxContainer

# Mağaza: welcome carousel, featured games, deals and new releases.
# Built from the real PARDEX catalog; PARDEX has no payment system yet, so
# games show their availability instead of prices and the deals shelf says
# that no campaign is running.

signal navigate(page: String)
signal play_requested(game_id: String)
signal toast(message: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")
const SLIDE_SECONDS := 8.0
const HERO_HEIGHT := 300.0
const HERO_TITLE_HEIGHT := 80.0
const HERO_BODY_HEIGHT := 46.0

var _slide := 0
var _hero_art: TextureRect
var _hero_tag: Label
var _hero_title: Label
var _hero_body: Label
var _hero_dots: HBoxContainer
var _hero_features: Control
var _query := ""
var _featured: GridContainer
var _new_row: GridContainer
var _content_width := 1200.0


func _ready() -> void:
	# The layout lives in scenes/pages/store_page.tscn; building from code only
	# happens when the script runs without its scene (tools/bake_page_scenes.gd).
	if get_child_count() == 0:
		_build()
		UI.own(self)
	_bind()
	_render_shelves()
	_show_slide(0)
	var timer := Timer.new()
	timer.wait_time = SLIDE_SECONDS
	timer.autostart = true
	timer.timeout.connect(func(): if is_visible_in_tree(): _show_slide(_slide + 1))
	add_child(timer)
	visibility_changed.connect(func(): if is_visible_in_tree(): _render_shelves())


func _bind() -> void:
	_hero_art = %HeroArt
	_hero_tag = %HeroTag
	_hero_title = %HeroTitle
	_hero_body = %HeroBody
	_hero_dots = %HeroDots
	_hero_features = %HeroFeatures
	_featured = %FeaturedGrid
	_new_row = %NewGrid
	(%FeaturedLink as Button).pressed.connect(func(): navigate.emit("library"))
	(%NewLink as Button).pressed.connect(func(): navigate.emit("library"))
	(%ExploreButton as Button).pressed.connect(_explore_slide)
	(%WishButton as Button).pressed.connect(_toggle_slide_wishlist)
	(%PrevButton as Button).pressed.connect(func(): _show_slide(_slide - 1))
	(%NextButton as Button).pressed.connect(func(): _show_slide(_slide + 1))
	for index in _hero_dots.get_child_count():
		(_hero_dots.get_child(index) as Button).pressed.connect(_show_slide.bind(index))


func _build() -> void:
	add_theme_constant_override("separation", 0)
	var body := UI.vbox(16)
	add_child(UI.scroll_page(body))

	# Top bar search results replace the shelves while a query is typed.
	var results := UI.named(UI.vbox(14), "SearchResults") as VBoxContainer
	results.visible = false
	results.add_child(UI.named(UI.label("", 22, UI.TEXT, true), "SearchTitle"))
	results.add_child(UI.named(_grid(), "SearchGrid"))
	var no_results := UI.panel(14)
	no_results.custom_minimum_size.y = 120
	no_results.add_child(UI.empty_state("search", "Sonuç bulunamadı", "Farklı bir oyun adı ya da tür dene.", true))
	results.add_child(UI.named(no_results, "SearchEmpty"))
	body.add_child(results)

	var shelves := UI.named(UI.vbox(16), "Shelves") as VBoxContainer
	body.add_child(shelves)
	shelves.add_child(_build_hero())

	var featured_header := UI.section_header("Öne Çıkanlar", "Tümünü Gör", 22)
	featured_header.add_child(UI.pill("Editörün Seçimi", UI.GOLD, "crown", 11))
	featured_header.move_child(featured_header.get_child(-1), 1)
	UI.named(featured_header.get_node("Link"), "FeaturedLink")
	shelves.add_child(featured_header)
	shelves.add_child(UI.named(_grid(), "FeaturedGrid"))

	var deals_header := UI.section_header("İndirimler", "Tümünü Gör", 20, "percent", UI.RED)
	deals_header.add_child(UI.label("Kaçırılmayacak fırsatlar, sınırlı süreli indirimler.", 13, UI.TEXT_2))
	deals_header.move_child(deals_header.get_child(-1), 2)
	(deals_header.get_node("Link") as Button).visible = false
	shelves.add_child(deals_header)
	var deals := UI.panel(14)
	deals.custom_minimum_size.y = 76
	deals.add_child(UI.empty_state("percent", "Şu an aktif indirim yok", "Kampanyalar başladığında burada görünecek.", true))
	shelves.add_child(deals)

	var new_header := UI.section_header("Yeni Gelenler", "Tümünü Gör", 20, "sparkles", UI.ACCENT)
	new_header.add_child(UI.label("En yeni oyunlar şimdi PARDEX'te.", 13, UI.TEXT_2))
	new_header.move_child(new_header.get_child(-1), 2)
	UI.named(new_header.get_node("Link"), "NewLink")
	shelves.add_child(new_header)
	shelves.add_child(UI.named(_grid(), "NewGrid"))


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	return grid


## Called by the top bar search while Mağaza is open.
func set_query(query: String) -> void:
	_query = query.strip_edges().to_lower()
	if is_node_ready():
		_render_search()


func _render_search() -> void:
	var searching := not _query.is_empty()
	(%Shelves as Control).visible = not searching
	(%SearchResults as Control).visible = searching
	if not searching:
		return
	var grid := %SearchGrid as GridContainer
	UI.clear(grid)
	var count := 0
	for entry in Catalog.GAMES:
		var haystack := " ".join([str(entry["title"]), " ".join(entry["genres"]), str(entry["tagline"])]).to_lower()
		if _query in haystack:
			grid.add_child(_featured_card(entry))
			count += 1
	(%SearchTitle as Label).text = "Arama sonuçları (%d)" % count
	grid.visible = count > 0
	(%SearchEmpty as Control).visible = count == 0


func apply_layout(content_width: float) -> void:
	_content_width = content_width
	(%SearchGrid as GridContainer).columns = 3 if content_width >= 1020.0 else 2
	_featured.columns = 3 if content_width >= 1020.0 else 2
	_new_row.columns = 3 if content_width >= 1100.0 else 2
	if _hero_features != null:
		_hero_features.visible = content_width >= 900.0


# ------------------------------------------------------------------ hero

func _slides() -> Array:
	var result := [{
		"tag": "OYUNLARIN YENİ EVİ",
		"title": "PARDEX Mağazaya Hoş Geldin",
		"body": "Yeni oyunları keşfet, arkadaşlarınla oyna\nve öne çıkan içerikleri hemen incele.",
		"banner": "res://assets/ui/home_hero_banner.png",
		"game": "",
	}]
	for entry in Catalog.GAMES:
		result.append({
			"tag": str(entry["badge"]).to_upper(),
			"title": str(entry["title"]),
			"body": str(entry["tagline"]),
			"banner": str(entry["banner"]),
			"game": str(entry["id"]),
		})
	return result


func _build_hero() -> Control:
	# Fixed outer height plus fixed two-line text slots keeps every carousel slide
	# on exactly the same geometry, regardless of title/body length.
	var frame := UI.image(null, Vector2(0, HERO_HEIGHT), 16)
	frame.add_theme_stylebox_override("panel", UI.glow_style(0, 16))
	UI.named(frame.get_node("Art"), "HeroArt")
	frame.add_child(UI.shade(0.95, true))
	frame.add_child(UI.shade(0.55))

	var row := UI.hbox(20)
	frame.add_child(UI.margin(row, 30, 20, 24, 16))
	var text := UI.vbox(4)
	UI.expand(text)
	row.add_child(text)
	var tag_row := UI.hbox(8)
	tag_row.add_child(UI.icon("crown", 15, UI.ACCENT))
	tag_row.add_child(UI.named(UI.label("", 12, UI.ACCENT, true), "HeroTag"))
	var tag_holder := UI.panel(0, UI.box(Color(UI.BG, 0.6), 8, UI.BORDER_HI, 1, 8))
	tag_holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag_holder.add_child(tag_row)
	text.add_child(tag_holder)

	var title_slot := Control.new()
	title_slot.custom_minimum_size.y = HERO_TITLE_HEIGHT
	title_slot.clip_contents = true
	text.add_child(title_slot)
	var title := UI.named(UI.label("", 34, UI.TEXT, true), "HeroTitle") as Label
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	title_slot.add_child(title)

	var body_slot := Control.new()
	body_slot.custom_minimum_size.y = HERO_BODY_HEIGHT
	body_slot.clip_contents = true
	text.add_child(body_slot)
	var hero_body := UI.named(UI.label("", 14, UI.TEXT_2), "HeroBody") as Label
	hero_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_body.max_lines_visible = 2
	hero_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body_slot.add_child(hero_body)

	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(gap)
	var actions := UI.hbox(12)
	text.add_child(actions)
	var explore := UI.button("Şimdi İncele", "primary", 14, 44, "arrow_right")
	explore.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	explore.custom_minimum_size.x = 190
	actions.add_child(UI.named(explore, "ExploreButton"))
	var wish := UI.button("İstek Listesi", "ghost", 14, 44, "heart")
	wish.custom_minimum_size.x = 170
	actions.add_child(UI.named(wish, "WishButton"))
	text.add_child(UI.vspacer())

	var pager := UI.hbox(8)
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.add_child(UI.named(UI.icon_button("chevron_left", "Önceki", 24), "PrevButton"))
	var dots := UI.named(UI.hbox(7), "HeroDots")
	pager.add_child(dots)
	for index in _slides().size():
		var dot := Button.new()
		dot.custom_minimum_size = Vector2(9, 9)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.focus_mode = Control.FOCUS_NONE
		dot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		dot.name = "Dot%d" % index
		dots.add_child(dot)
	pager.add_child(UI.named(UI.icon_button("chevron_right", "Sonraki", 24), "NextButton"))
	text.add_child(pager)

	var features := UI.feature_card([
		["star", "PARDEX Orijinalleri", "PARDEX için geliştirilen oyunlar."],
		["check_circle", "Güvenli Oyun Oturumu", "Biletli, korumalı bağlantı."],
		["gamepad", "Online Odalar", "Kodla katıl, birlikte oyna."],
		["friends", "Aktif Topluluk", "Arkadaşların seni bekliyor."],
	], 300)
	row.add_child(UI.named(features, "HeroFeatures"))
	return frame


func _show_slide(index: int) -> void:
	var slides := _slides()
	_slide = posmod(index, slides.size())
	var slide: Dictionary = slides[_slide]
	_hero_art.texture = Catalog.texture(str(slide["banner"]))
	_hero_tag.text = str(slide["tag"])
	_hero_title.text = str(slide["title"])
	_hero_body.text = str(slide["body"])
	for dot_index in _hero_dots.get_child_count():
		var dot := _hero_dots.get_child(dot_index) as Button
		var style := UI.box(UI.ACCENT if dot_index == _slide else Color(1, 1, 1, 0.3), 5)
		for state in ["normal", "hover", "pressed"]:
			dot.add_theme_stylebox_override(state, style)


func _explore_slide() -> void:
	var game_id := str(_slides()[_slide]["game"])
	if game_id.is_empty():
		navigate.emit("library")
	else:
		_open_game(game_id)


func _toggle_slide_wishlist() -> void:
	var game_id := str(_slides()[_slide]["game"])
	if game_id.is_empty():
		game_id = str(Catalog.GAMES[0]["id"])
	var added := Catalog.toggle_wishlist(game_id)
	toast.emit("%s istek listene %s." % [str(Catalog.game(game_id)["title"]), "eklendi" if added else "çıkarıldı"])
	_render_shelves()


# ------------------------------------------------------------------ shelves

func _render_shelves() -> void:
	UI.clear(_featured)
	for entry in Catalog.GAMES:
		_featured.add_child(_featured_card(entry))
	UI.clear(_new_row)
	for entry in Catalog.GAMES:
		_new_row.add_child(_new_card(entry))


func _heart(game_id: String, icon_size := 34.0) -> Button:
	var wished := Catalog.is_wishlisted(game_id)
	var heart := UI.icon_button("heart_fill" if wished else "heart", "İstek listesi", icon_size, UI.RED if wished else UI.TEXT, true)
	heart.add_theme_stylebox_override("normal", UI.box(Color(UI.BG, 0.65), 9, Color(1, 1, 1, 0.18), 1))
	heart.pressed.connect(func():
		var added := Catalog.toggle_wishlist(game_id)
		toast.emit("%s istek listene %s." % [str(Catalog.game(game_id)["title"]), "eklendi" if added else "çıkarıldı"])
		_render_shelves()
	)
	return heart


func _availability(entry: Dictionary) -> Control:
	var state: Array = Catalog.status(str(entry["id"]))
	var color: Color = {"green": UI.GREEN, "amber": UI.AMBER, "muted": UI.TEXT_3}[state[2]]
	var row := UI.hbox(10)
	row.add_child(UI.pill(str(state[0]), color, str(state[1]), 12, state[2] == "green"))
	return row


func _badge_color(badge: String) -> Color:
	match badge:
		"Popüler": return UI.RED
		"Editörün Seçimi": return UI.GOLD
		_: return UI.ACCENT


func _badge_icon(badge: String) -> String:
	match badge:
		"Popüler": return "fire"
		"Editörün Seçimi": return "crown"
		_: return "sparkles"


func _featured_card(entry: Dictionary) -> Control:
	var game_id := str(entry["id"])
	var frame := UI.image(Catalog.texture(str(entry["cover"])), Vector2(0, 190), 12)
	UI.expand(frame)
	frame.add_theme_stylebox_override("panel", UI.card_style(0))
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame.gui_input.connect(_on_card_input.bind(game_id))
	frame.add_child(UI.shade(0.95))
	var column := UI.vbox(2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(UI.margin(column, 12, 12, 12, 12))
	var badge := str(entry["badge"])
	column.add_child(UI.pill(badge, _badge_color(badge), _badge_icon(badge), 12))
	column.add_child(UI.vspacer())
	var bottom := UI.hbox(10)
	column.add_child(bottom)
	var info := UI.vbox(3)
	UI.expand(info)
	info.add_child(UI.fit(UI.label(str(entry["title"]), 18, UI.TEXT, true)))
	info.add_child(UI.fit(UI.label("   ".join(entry["genres"]), 13, UI.TEXT_2)))
	info.add_child(_availability(entry))
	bottom.add_child(info)
	var heart := _heart(game_id, 38)
	heart.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(heart)
	return frame


func _new_card(entry: Dictionary) -> Control:
	var game_id := str(entry["id"])
	var card := UI.panel(0, UI.card_style(0))
	UI.expand(card)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_card_input.bind(game_id))
	var row := UI.hbox(12)
	card.add_child(row)
	var art := UI.image(Catalog.texture(str(entry["cover"])), Vector2(130, 80), 12)
	var art_column := UI.vbox(0)
	art_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_row := UI.hbox(0)
	badge_row.add_child(UI.spacer())
	badge_row.add_child(UI.pill("Yeni", UI.ACCENT, "", 11, true))
	art_column.add_child(badge_row)
	art.add_child(UI.margin(art_column, 6, 6, 6, 6))
	row.add_child(art)
	var text := UI.vbox(3)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.expand(text)
	text.add_child(UI.fit(UI.label(str(entry["title"]), 14, UI.TEXT, true)))
	text.add_child(UI.fit(UI.label("  ".join(entry["genres"]), 12, UI.TEXT_3)))
	text.add_child(_availability(entry))
	row.add_child(text)
	var heart := _heart(game_id, 32)
	heart.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(UI.margin(heart, 0, 8, 10, 8))
	return card


func _on_card_input(event: InputEvent, game_id: String) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		_open_game(game_id)


func _open_game(game_id: String) -> void:
	var entry := Catalog.game(game_id)
	if bool(entry.get("playable", false)):
		play_requested.emit(game_id)
	else:
		toast.emit("%s çok yakında PARDEX'te. İstek listene ekleyebilirsin." % str(entry.get("title", "Bu oyun")))
