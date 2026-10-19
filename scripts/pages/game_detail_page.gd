extends VBoxContainer

signal back_requested
signal play_requested(game_id: String)
signal uninstall_requested(game_id: String)

const Icons := preload("res://scripts/ui/pardex_icons.gd")

const Catalog := preload("res://scripts/data/pardex_catalog.gd")
const Distribution := preload("res://scripts/data/pardex_distribution.gd")

var game_id := ""
var _busy := false
var _images: Array[Texture2D] = []
var _image_index := 0


func _ready() -> void:
	for entry in [[%BackButton, "arrow_left"], [%WishButton, "heart"], [%FavoriteButton, "star"], [%UninstallButton, "trash"], [%PreviousImage, "chevron_left"], [%NextImage, "chevron_right"], [%EnlargeButton, "image"]]:
		(entry[0] as Button).icon = Icons.texture(str(entry[1]))
	%PreviousImage.text = ""
	%PreviousImage.tooltip_text = "Önceki görüntü"
	%NextImage.text = ""
	%NextImage.tooltip_text = "Sonraki görüntü"
	%BackButton.pressed.connect(func(): back_requested.emit())
	%ActionButton.pressed.connect(func(): play_requested.emit(game_id))
	%UninstallButton.pressed.connect(func(): uninstall_requested.emit(game_id))
	%WishButton.pressed.connect(func():
		Catalog.toggle_wishlist(game_id)
		refresh()
	)
	%FavoriteButton.pressed.connect(func():
		Catalog.toggle_favorite(game_id)
		refresh()
	)
	%PreviousImage.pressed.connect(func(): _show_image(_image_index - 1))
	%NextImage.pressed.connect(func(): _show_image(_image_index + 1))
	%EnlargeButton.pressed.connect(_enlarge_image)
	%Screenshot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_enlarge_image()
	)


func _enlarge_image() -> void:
	if _images.is_empty():
		return
	%LargeImage.texture = _images[_image_index]
	%ImageDialog.popup_centered(Vector2i(860, 540).min(Vector2i(get_viewport_rect().size) - Vector2i(40, 80)))


func show_game(id: String) -> void:
	game_id = id
	%Operation.text = ""
	%Scroll.scroll_vertical = 0
	_image_index = 0
	refresh()


func refresh() -> void:
	if game_id.is_empty() or not is_node_ready():
		return
	var entry := Catalog.game(game_id)
	if entry.is_empty():
		return
	%GameTitle.text = str(entry["title"])
	%Tagline.text = str(entry.get("tagline", ""))
	%Banner.texture = Catalog.texture(str(entry.get("banner", "")))
	%Facts.text = "  •  ".join(entry.get("genres", [])) + "\n" + str(entry.get("players", ""))
	%About.text = _text(entry, "long_description", str(entry.get("tagline", "")))
	%Requirements.text = _text(entry, "requirements")
	%ReleaseNotes.text = _text(entry, "release_notes")
	%Modes.text = _text(entry, "connection_modes")
	%Version.text = "Sürüm " + str(entry.get("version", "—"))
	var installed := Catalog.is_installed(game_id)
	var downloaded := not Distribution.executable(game_id).is_empty()
	%UninstallButton.visible = downloaded
	%FavoriteButton.visible = installed
	%FavoriteButton.text = "Favorilerden çıkar" if Catalog.favorites().has(game_id) else "Favorilere ekle"
	%WishButton.text = "İstek listesinden çıkar" if Catalog.is_wishlisted(game_id) else "İstek listesine ekle"
	%FavoriteButton.icon = Icons.texture("star_fill" if Catalog.favorites().has(game_id) else "star")
	%WishButton.icon = Icons.texture("heart_fill" if Catalog.is_wishlisted(game_id) else "heart")
	%ActionButton.icon = Icons.texture("clock" if _busy else ("play" if installed else "download"))
	%Playtime.visible = installed
	for record in Catalog.games_with_stats():
		if str(record["id"]) == game_id:
			%Playtime.text = "Oynama süresi: " + Catalog.hours(int(record["playtime"]))
			break
	%ActionButton.text = "İşlem sürüyor…" if _busy else Catalog.action_label(game_id)
	%ActionButton.disabled = _busy or not bool(entry.get("playable", false))
	%UninstallButton.disabled = _busy
	_images.clear()
	for asset in entry.get("screenshots", []):
		var path := Distribution.art_path(asset)
		if not path.is_empty():
			var texture := Catalog.texture(path)
			if texture != null:
				_images.append(texture)
	%Gallery.visible = not _images.is_empty()
	%NoScreenshots.visible = _images.is_empty()
	if not _images.is_empty():
		_show_image(_image_index)


func _text(entry: Dictionary, field: String, fallback := "") -> String:
	var value := str(entry.get(field, fallback)).strip_edges()
	return value if not value.is_empty() else "Henüz paylaşılmadı."


func set_operation(active: bool, message: String) -> void:
	_busy = active
	%Operation.text = message
	refresh()


func _show_image(index: int) -> void:
	if _images.is_empty():
		return
	_image_index = posmod(index, _images.size())
	%Screenshot.texture = _images[_image_index]
	%ImageCount.text = "%d / %d" % [_image_index + 1, _images.size()]
	%PreviousImage.disabled = _images.size() < 2
	%NextImage.disabled = _images.size() < 2


func apply_layout(content_width: float) -> void:
	%HeroColumns.vertical = content_width < 850.0
	%Info.custom_minimum_size.x = 0.0 if content_width < 850.0 else 290.0
	%TextColumns.vertical = content_width < 850.0
