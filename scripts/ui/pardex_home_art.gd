extends Node

# Applies the generated PARDEX artwork to the dynamically-built Home screen.
# Artwork stays separate from layout logic so assets can be replaced later
# without rebuilding the responsive UI.

const RETRY_SECONDS := 0.20

const HERO_ART := "res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_38-1.png"
const RECENT_ART := [
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_40-2.png",
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_42-3.png",
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_44-4.png",
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_46-5.png",
]
const AGENDA_ART := {
	"Platform Hazırlanıyor": "res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_48-6.png",
	"Sosyal Özellikler Aktif": "res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_50-7.png",
	"Yeni Oyunlar Yakında": "res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_52-8.png",
}
const QUICK_ART := "res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_58-9.png"

var _applied := false


func _ready() -> void:
	call_deferred("_bind_home")


func _bind_home() -> void:
	if _applied:
		return
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null or scene.name != "Pardex":
		_retry()
		return

	var home := scene.get_node_or_null("MainMargin/MainVBox/HomeContent") as Control
	if home == null:
		_retry()
		return

	_apply_hero(home)
	_apply_agenda(home)
	_apply_recent(home)
	_apply_quick_start(home)
	_applied = true


func _retry() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(RETRY_SECONDS)
	timer.timeout.connect(_bind_home)


func _texture(path: String) -> Texture2D:
	var resource := ResourceLoader.load(path)
	return resource as Texture2D


func _apply_hero(home: Node) -> void:
	var hero := _find_named(home, "HomeHero") as PanelContainer
	var texture := _texture(HERO_ART)
	if hero == null or texture == null:
		return

	hero.clip_contents = true
	var artwork := TextureRect.new()
	artwork.name = "HeroArtwork"
	artwork.texture = texture
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	artwork.modulate = Color(0.90, 0.96, 1.0, 0.92)
	hero.add_child(artwork)
	hero.move_child(artwork, 0)

	# Keep a dark veil over the art so the welcome copy remains readable.
	for child in hero.get_children():
		if child is ColorRect:
			var veil := child as ColorRect
			veil.color = Color(0.004, 0.018, 0.035, 0.47)
			break

	# The generated banner already carries the PARDEX monument, so hide the
	# temporary oversized P watermark from the placeholder version.
	for child in hero.get_children():
		if child is Label and (child as Label).text == "P":
			(child as Label).hide()


func _apply_agenda(home: Node) -> void:
	for title_text in AGENDA_ART.keys():
		var title := _find_label(home, str(title_text))
		var texture := _texture(str(AGENDA_ART[title_text]))
		if title == null or texture == null:
			continue

		var texts := title.get_parent()
		if texts == null:
			continue
		var row := texts.get_parent() as HBoxContainer
		if row == null or row.get_child_count() == 0:
			continue
		var icon_box := row.get_child(0) as PanelContainer
		if icon_box == null:
			continue
		_replace_icon_box(icon_box, texture, 54.0)


func _apply_recent(home: Node) -> void:
	var heading := _find_label(home, "Son Oynananlar")
	if heading == null:
		return
	var section := heading.get_parent()
	if section == null or section.get_parent() == null:
		return
	section = section.get_parent()
	if not section is VBoxContainer or section.get_child_count() < 2:
		return

	var card_host := section.get_child(1)
	var cards := card_host.get_children()
	for index in range(mini(cards.size(), RECENT_ART.size())):
		var card := cards[index] as PanelContainer
		var texture := _texture(RECENT_ART[index])
		if card == null or texture == null:
			continue
		_apply_recent_card(card, texture)


func _apply_recent_card(card: PanelContainer, texture: Texture2D) -> void:
	card.clip_contents = true
	var art_label := _find_first_label_text(card, ["⌁", "○", "▦", "+"])
	if art_label == null:
		return
	var holder := art_label.get_parent() as Container
	if holder == null:
		return
	var insert_index := art_label.get_index()
	art_label.hide()

	var artwork := TextureRect.new()
	artwork.name = "CardArtwork"
	artwork.texture = texture
	artwork.custom_minimum_size = Vector2(0, 150)
	artwork.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	artwork.size_flags_vertical = Control.SIZE_EXPAND_FILL
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	artwork.modulate = Color(0.88, 0.94, 1.0, 0.88)
	holder.add_child(artwork)
	holder.move_child(artwork, insert_index)


func _apply_quick_start(home: Node) -> void:
	var heading := _find_label(home, "Hızlı Başlat")
	var texture := _texture(QUICK_ART)
	if heading == null or texture == null:
		return
	var column := heading.get_parent()
	if column == null:
		return

	for child in column.get_children():
		if not child is PanelContainer:
			continue
		var plus := _find_first_label_text(child, ["+"])
		if plus == null:
			continue
		var holder := plus.get_parent() as HBoxContainer
		if holder == null:
			continue
		var insert_index := plus.get_index()
		plus.hide()

		var icon := TextureRect.new()
		icon.name = "QuickArtwork"
		icon.texture = texture
		icon.custom_minimum_size = Vector2(44, 44)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color(0.88, 0.95, 1.0, 0.90)
		holder.add_child(icon)
		holder.move_child(icon, insert_index)


func _replace_icon_box(icon_box: PanelContainer, texture: Texture2D, size_value: float) -> void:
	icon_box.clip_contents = true
	for child in icon_box.get_children():
		if child is Label:
			(child as Label).hide()

	var art := TextureRect.new()
	art.name = "AgendaArtwork"
	art.texture = texture
	art.custom_minimum_size = Vector2(size_value, size_value)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.modulate = Color(0.93, 0.97, 1.0, 0.96)
	icon_box.add_child(art)


func _find_named(root: Node, wanted: String) -> Node:
	if root.name == wanted:
		return root
	for child in root.get_children():
		var result := _find_named(child, wanted)
		if result != null:
			return result
	return null


func _find_label(root: Node, text_value: String) -> Label:
	if root is Label and (root as Label).text == text_value:
		return root as Label
	for child in root.get_children():
		var result := _find_label(child, text_value)
		if result != null:
			return result
	return null


func _find_first_label_text(root: Node, values: Array) -> Label:
	if root is Label and (root as Label).text in values:
		return root as Label
	for child in root.get_children():
		var result := _find_first_label_text(child, values)
		if result != null:
			return result
	return null
