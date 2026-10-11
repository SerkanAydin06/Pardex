extends VBoxContainer

# Mağaza: welcome carousel, featured games, deals and new releases.
# Built from the real PARDEX catalog; PARDEX has no payment system yet, so
# games show their availability instead of prices and the deals shelf says
# that no campaign is running.

signal navigate(page: String)
signal play_requested(game_id: String)
signal toast(message: String)

const UI := preload("res://scripts/ui/pardex_ui.gd")
const FeaturedCardScene := preload("res://scenes/ui/store_featured_card.tscn")
const NewCardScene := preload("res://scenes/ui/store_new_card.tscn")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")
const SLIDE_SECONDS := 8.0
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
	# Layout is owned by scenes/pages; runtime code only binds data and actions.
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


# Both store card layouts are editable templates in scenes/ui.
func _featured_card(entry: Dictionary) -> Control:
	var game_id := str(entry["id"])
	var card := FeaturedCardScene.instantiate() as PanelContainer
	card.gui_input.connect(_on_card_input.bind(game_id))
	(card.get_node("Art") as TextureRect).texture = Catalog.texture(str(entry["cover"]))
	var badge := str(entry["badge"])
	(card.get_node("Content/Column/BadgeSlot") as HBoxContainer).add_child(UI.pill(badge, _badge_color(badge), _badge_icon(badge), 12))
	(card.get_node("Content/Column/Bottom/Info/Title") as Label).text = str(entry["title"])
	(card.get_node("Content/Column/Bottom/Info/Genres") as Label).text = "   ".join(entry["genres"])
	(card.get_node("Content/Column/Bottom/Info/AvailabilitySlot") as HBoxContainer).add_child(_availability(entry))
	var heart := _heart(game_id, 38)
	heart.size_flags_vertical = Control.SIZE_SHRINK_END
	(card.get_node("Content/Column/Bottom/HeartSlot") as HBoxContainer).add_child(heart)
	return card


func _new_card(entry: Dictionary) -> Control:
	var game_id := str(entry["id"])
	var card := NewCardScene.instantiate() as PanelContainer
	card.gui_input.connect(_on_card_input.bind(game_id))
	(card.get_node("Row/Artwork/Art") as TextureRect).texture = Catalog.texture(str(entry["cover"]))
	(card.get_node("Row/Artwork/BadgeSlot") as HBoxContainer).add_child(UI.pill("Yeni", UI.ACCENT, "", 11, true))
	(card.get_node("Row/Info/Title") as Label).text = str(entry["title"])
	(card.get_node("Row/Info/Genres") as Label).text = "  ".join(entry["genres"])
	(card.get_node("Row/Info/AvailabilitySlot") as HBoxContainer).add_child(_availability(entry))
	var heart := _heart(game_id, 32)
	heart.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	(card.get_node("Row/HeartSlot") as MarginContainer).add_child(heart)
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
