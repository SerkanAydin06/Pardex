extends Control

# PARDEX shell: top bar, sidebar navigation (Mağaza, Kütüphane, Arkadaşlar,
# Profil), page switching, settings, window state, game launch and playtime.
# Each page is its own script under scripts/pages/ and talks back through
# navigate / play_requested / toast signals.

const APP_VERSION := "0.1.0"
const SETTINGS_PATH := "user://pardex.cfg"
const DEFAULT_SERVER_URL := ""
const DEFAULT_WINDOW_SIZE := Vector2i(1440, 900)
const MIN_WINDOW_SIZE := Vector2i(1024, 640)
const WINDOW_STATE_SAVE_INTERVAL := 1.0
const SESSION_POLL_INTERVAL := 5.0
const UI := preload("res://scripts/ui/pardex_ui.gd")
const Icons := preload("res://scripts/ui/pardex_icons.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")

const WINDOW_NARROW := 1280
const NAV := {
	"StoreButton": ["store", "store"],
	"LibraryButton": ["library", "library"],
	"FriendsButton": ["friends", "friends"],
	"ProfileButton": ["profile", "profile"],
}

@onready var toast_panel: PanelContainer = %ToastPanel
@onready var toast_label: Label = %ToastLabel
@onready var profile_name_label: Label = %UserName
@onready var online_state_button: Button = %OnlineState

var search_field: LineEdit
var _store_page: VBoxContainer
var _library_page: VBoxContainer
var _social_page: VBoxContainer
var _profile_page: VBoxContainer
var _settings_content: VBoxContainer
var _presence_menu: PopupMenu
var _current_page := ""
var _previous_page := "store"
var _avatar_dialog: FileDialog
# Page name -> the node shown for it.
var _pages: Dictionary = {}
var _display_name := "Pardus"
var _server_url := DEFAULT_SERVER_URL
var _game_launch_in_progress := false
var _toast_revision := 0
var _start_fullscreen := false
var _saved_window_size := DEFAULT_WINDOW_SIZE
var _saved_window_position := Vector2i(-1, -1)
var _saved_window_maximized := false
var _window_state_save_elapsed := 0.0
# pid -> {"game": id, "started": unix} for games PARDEX launched.
var _sessions: Dictionary = {}
var _session_poll_elapsed := 0.0


func _ready() -> void:
	theme = UI.app_theme()
	_build_search()
	_style_brand()
	_load_settings()
	_apply_window_preferences()
	_create_pages()
	_wire_navigation()
	_wire_online_signals()
	_apply_profile()
	_update_connection_ui(PardexOnline.connection_state)
	toast_panel.hide()
	Catalog.joined_at()
	resized.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_navigate("store")

	PardexOnline.configure(_server_url, _display_name)
	PardexOnline.connect_server()


# ------------------------------------------------------------------ shell

func _build_search() -> void:
	search_field = UI.search_field("Oyun, tür, stüdyo veya içerik ara...", 38)
	search_field.name = "LibrarySearch"
	search_field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	search_field.add_theme_font_size_override("font_size", 14)
	search_field.text_changed.connect(_on_search_changed)
	%SearchSlot.add_child(search_field)


# PARDEX wordmark in Orbitron (SIL Open Font License, assets/fonts).
func _style_brand() -> void:
	var font_file := load("res://assets/fonts/Orbitron.ttf") as FontFile
	if font_file == null:
		return
	var brand_font := FontVariation.new()
	brand_font.base_font = font_file
	brand_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	brand_font.spacing_glyph = 2
	var title := %Brand.get_node("BrandTitle") as Label
	title.add_theme_font_override("font", brand_font)
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_constant_override("outline_size", 0)
	title.add_theme_color_override("font_shadow_color", Color(UI.ACCENT, 0.45))
	title.add_theme_constant_override("shadow_outline_size", 6)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)


func _create_pages() -> void:
	_store_page = _bind_page("store", "StorePage")
	_library_page = _bind_page("library", "LibraryPage")
	_social_page = _bind_page("friends", "FriendsPage")
	_profile_page = _bind_page("profile", "ProfilePage")
	_bind_page("settings", "SettingsPage")
	_settings_content = %Pages.get_node("SettingsPage/%SettingsContent") as VBoxContainer
	_bind_settings_page()
	for page in [_store_page, _library_page, _social_page, _profile_page]:
		if page.has_signal("navigate"):
			page.navigate.connect(_navigate)
		if page.has_signal("play_requested"):
			page.play_requested.connect(_play_game)
		if page.has_signal("toast"):
			page.toast.connect(_show_toast)


# Pages are real scene instances (scenes/pages/*.tscn) under %Pages so they
# can be edited in the Godot editor.
func _bind_page(page_name: String, node_name: String) -> VBoxContainer:
	var page := %Pages.get_node(node_name) as VBoxContainer
	page.hide()
	_pages[page_name] = page
	return page


func _bind_settings_page() -> void:
	(_settings_content.get_node("ProfilePanel/VBox/ProfileRow/SaveProfileButton") as Button).pressed.connect(_save_profile_from_settings)
	(_settings_content.get_node("OnlinePanel/VBox/ServerRow/ConnectButton") as Button).pressed.connect(_save_online_settings_and_connect)
	(_settings_content.get_node("DisplayPanel/VBox/FullscreenOnStart") as CheckButton).toggled.connect(_on_fullscreen_toggled)
	var settings_page := _pages["settings"] as Control
	(settings_page.get_node("%BackButton") as Button).pressed.connect(_navigate_back)
	(settings_page.get_node("%ChooseAvatarButton") as Button).pressed.connect(_choose_avatar)
	(settings_page.get_node("%RemoveAvatarButton") as Button).pressed.connect(func():
		PardexOnline.clear_avatar()
		_show_toast("Profil resmi kaldırıldı.")
	)
	PardexOnline.avatar_ready.connect(func(_account_id): _render_avatar_preview())


# Ayarlar is opened from Profil ("Profili Düzenle") or the gear; Geri returns.
func _navigate_back() -> void:
	_navigate(_previous_page if _pages.has(_previous_page) else "store")


func _render_avatar_preview() -> void:
	var settings_page := _pages["settings"] as Control
	var preview := settings_page.get_node("%AvatarPreview") as Control
	UI.clear(preview)
	preview.add_child(UI.avatar(_display_name, 64, "", UI.ACCENT, PardexOnline.my_avatar_texture()))
	(settings_page.get_node("%RemoveAvatarButton") as Button).disabled = not PardexOnline.has_my_avatar()


func _choose_avatar() -> void:
	if _avatar_dialog == null:
		_avatar_dialog = FileDialog.new()
		_avatar_dialog.title = "Profil resmi seç"
		_avatar_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_avatar_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_avatar_dialog.use_native_dialog = true
		_avatar_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Resimler"])
		_avatar_dialog.file_selected.connect(func(path: String):
			var error := PardexOnline.set_avatar_from_file(path)
			_show_toast(error if not error.is_empty() else "Profil resmi güncellendi.")
		)
		add_child(_avatar_dialog)
	_avatar_dialog.popup_centered_ratio(0.6)


func _wire_navigation() -> void:
	for button_name in NAV:
		var button := get_node("%" + button_name) as Button
		var spec: Array = NAV[button_name]
		button.pressed.connect(_navigate.bind(str(spec[0])))
		button.icon = Icons.texture(str(spec[1]), 52)
		button.expand_icon = false
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.custom_minimum_size.y = 62
		button.add_theme_font_size_override("font_size", 19)
		button.add_theme_constant_override("icon_max_width", 26)
		button.add_theme_constant_override("h_separation", 20)
	var settings := %SettingsButton as Button
	settings.icon = Icons.texture("gear", 44)
	settings.add_theme_constant_override("icon_max_width", 22)
	settings.add_theme_color_override("icon_normal_color", UI.TEXT_2)
	settings.add_theme_color_override("icon_hover_color", UI.TEXT)
	settings.pressed.connect(_navigate.bind("settings"))
	online_state_button.pressed.connect(_open_presence_menu)
	_build_presence_menu()


func _navigate(page_name: String) -> void:
	if not _pages.has(page_name):
		return
	if page_name == "settings":
		_prepare_settings()
	for key in _pages:
		(_pages[key] as Control).visible = key == page_name
	if _current_page != page_name and _current_page != "settings" and not _current_page.is_empty():
		_previous_page = _current_page
	_current_page = page_name
	_update_search_for_page()
	var page := _pages[page_name] as Control
	page.modulate.a = 0.0
	create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).tween_property(page, "modulate:a", 1.0, 0.15)
	_render_navigation()


func _render_navigation() -> void:
	for button_name in NAV:
		var button := get_node("%" + button_name) as Button
		var selected := str(NAV[button_name][0]) == _current_page
		button.add_theme_stylebox_override("normal", _nav_style(selected, false))
		button.add_theme_stylebox_override("hover", _nav_style(selected, true))
		button.add_theme_stylebox_override("pressed", _nav_style(true, true))
		var color := UI.TEXT if selected else UI.TEXT_2
		button.add_theme_color_override("font_color", color)
		button.add_theme_color_override("font_hover_color", UI.TEXT)
		button.add_theme_color_override("icon_normal_color", UI.ACCENT if selected else UI.TEXT_2)
		button.add_theme_color_override("icon_hover_color", UI.ACCENT if selected else UI.TEXT)
		button.add_theme_color_override("icon_pressed_color", UI.ACCENT)


func _nav_style(selected: bool, hovered: bool) -> StyleBoxFlat:
	var style := UI.box(Color.TRANSPARENT, 12)
	style.content_margin_left = 22
	style.content_margin_right = 12
	if selected:
		style.bg_color = Color("123a68") if hovered else Color("0f3160")
		style.border_color = Color(UI.ACCENT, 0.7)
		style.set_border_width_all(1)
		style.border_width_left = 4
		style.shadow_color = Color(UI.ACCENT, 0.22)
		style.shadow_size = 10
	elif hovered:
		style.bg_color = Color(1, 1, 1, 0.05)
	return style


# The top bar search belongs to the open page: Mağaza and Kütüphane each keep
# their own query; pages without searchable content hide the field.
const SEARCH_PLACEHOLDERS := {
	"store": "Mağazada oyun, tür ara...",
	"library": "Kütüphanende ara...",
}
var _search_queries := {"store": "", "library": ""}


func _update_search_for_page() -> void:
	var searchable := SEARCH_PLACEHOLDERS.has(_current_page)
	search_field.visible = searchable
	if not searchable:
		search_field.release_focus()
		return
	search_field.placeholder_text = str(SEARCH_PLACEHOLDERS[_current_page])
	search_field.set_block_signals(true)
	search_field.text = str(_search_queries[_current_page])
	search_field.set_block_signals(false)


func _on_search_changed(query: String) -> void:
	if not _search_queries.has(_current_page):
		return
	_search_queries[_current_page] = query
	if _current_page == "store":
		_store_page.set_query(query)
	else:
		_library_page.set_query(query)


# Steam-style reflow: sidebar and content always split the window (Body is an
# HBoxContainer); layout choices use the window width, never content width.
func _apply_responsive_layout() -> void:
	var width := size.x
	if width <= 1.0:
		return
	var narrow := width <= WINDOW_NARROW
	var sidebar_width := 214.0 if narrow else 258.0
	%Sidebar.custom_minimum_size.x = sidebar_width
	%Brand.custom_minimum_size.x = sidebar_width - 22.0
	var outer := 12 if narrow else 18
	var main_margin := %MainMargin as MarginContainer
	for side in ["margin_left", "margin_right"]:
		main_margin.add_theme_constant_override(side, outer)
	%SearchSlot.custom_minimum_size.x = 200.0 if narrow else 280.0
	for button_name in NAV:
		var button := get_node("%" + button_name) as Button
		button.add_theme_font_size_override("font_size", 16 if narrow else 19)
		button.add_theme_constant_override("h_separation", 14 if narrow else 20)
	%WindowChrome.get_node("SecondaryAction").visible = true
	%WindowChrome.get_node("Separator").visible = true
	var content_width := width - sidebar_width - float(outer * 2)
	for page in [_store_page, _library_page, _social_page, _profile_page]:
		page.apply_layout(content_width)

# ------------------------------------------------------------------ presence

func _build_presence_menu() -> void:
	_presence_menu = PopupMenu.new()
	add_child(_presence_menu)
	for entry in [["online", "●  Çevrimiçi"], ["away", "◐  Boşta"], ["busy", "●  Meşgul"]]:
		_presence_menu.add_item(str(entry[1]))
		_presence_menu.set_item_metadata(_presence_menu.item_count - 1, entry[0])
	_presence_menu.index_pressed.connect(func(index: int):
		PardexOnline.set_presence_status(str(_presence_menu.get_item_metadata(index)))
	)


func _open_presence_menu() -> void:
	if not PardexOnline.is_online():
		_show_toast("Durum seçmek için PARDEX Online bağlantısı gerekli.")
		return
	var rect := online_state_button.get_global_rect()
	var popup_position := Vector2i(roundi(rect.position.x), roundi(rect.position.y - 96.0))
	_presence_menu.popup(Rect2i(popup_position, Vector2i.ZERO))


func _render_presence() -> void:
	var presence := PardexOnline.effective_presence if PardexOnline.is_online() else "offline"
	if PardexOnline.connection_state == "connecting":
		online_state_button.text = "Bağlanıyor"
		online_state_button.add_theme_color_override("font_color", UI.AMBER)
	elif PardexOnline.is_host_closed():
		online_state_button.text = "Sunucu kapalı"
		online_state_button.add_theme_color_override("font_color", UI.TEXT_2)
	else:
		online_state_button.text = UI.presence_label(presence)
		online_state_button.add_theme_color_override("font_color", UI.presence_color(presence) if presence != "offline" else UI.TEXT_2)
	online_state_button.add_theme_color_override("font_hover_color", UI.TEXT)
	UI.clear(%AvatarSlot)
	%AvatarSlot.add_child(UI.avatar(_display_name, 52, presence, UI.ACCENT, PardexOnline.my_avatar_texture()))


func _wire_online_signals() -> void:
	PardexOnline.connection_state_changed.connect(_update_connection_ui)
	PardexOnline.presence_changed.connect(func(_presence): _render_presence())
	PardexOnline.avatar_ready.connect(func(_account_id): _render_presence())
	PardexOnline.online_error.connect(_show_toast)
	PardexOnline.game_start_requested.connect(_on_game_start_requested)
	PardexOnline.room_state_changed.connect(func(room: Dictionary):
		if not bool(room.get("launching", false)):
			_game_launch_in_progress = false
	)
	PardexOnline.room_left.connect(func(): _game_launch_in_progress = false)
	PardexGameLauncher.game_process_started.connect(_track_session)


func _update_connection_ui(state: String) -> void:
	var settings_state_label := _settings_content.get_node("OnlinePanel/VBox/State") as Label
	var text := "●  ÇEVRİMDIŞI"
	var color := UI.RED
	if state == "connecting":
		text = "●  BAĞLANIYOR"
		color = UI.AMBER
	elif state == "online":
		text = "●  ÇEVRİMİÇİ"
		color = UI.GREEN
	settings_state_label.text = text
	settings_state_label.add_theme_color_override("font_color", color)
	_render_presence()


# ------------------------------------------------------------------ games

func _play_game(game_id: String) -> void:
	var entry := Catalog.game(game_id)
	if entry.is_empty() or not bool(entry["playable"]):
		_show_toast("%s çok yakında PARDEX'te." % str(entry.get("title", "Bu oyun")))
		return
	# Korsanların Hazinesi is an online game: it starts from a party so every
	# player gets a secure PARDEX session ticket.
	_navigate("friends")
	if PardexOnline.current_room.is_empty():
		_show_toast("Korsanların Hazinesi için parti kur ya da bir partiye katıl.")
	else:
		_show_toast("Herkes hazır olduğunda parti kurucusu oyunu başlatır.")


func _on_game_start_requested(payload: Dictionary) -> void:
	var game_id := str(payload.get("game_id", ""))
	if game_id == "korsanlar":
		Catalog.record_launch(game_id)
	if _game_launch_in_progress:
		return
	if game_id != "korsanlar":
		_show_toast("Bu oyun için PARDEX launch desteği henüz hazır değil.")
		return
	if not PardexOnline.has_game_server_assignment():
		_show_toast("Korsan oyun sunucusu atanamadı.")
		return
	_game_launch_in_progress = true
	_launch_korsan_development_project()


func _launch_korsan_development_project() -> void:
	if not OS.has_feature("editor"):
		_handle_game_launch_failure("Windows oyun paketi henüz hazır değil.")
		return
	var project_path := _find_korsan_project_path()
	if project_path.is_empty():
		_handle_game_launch_failure("Korsanların Hazinesi geliştirme projesi PARDEX'in yan klasöründe bulunamadı.")
		return
	var launch_args := PackedStringArray(["--path", project_path, "--"])
	for argument in PardexOnline.build_game_launch_args("korsanlar"):
		launch_args.append(argument)
	var pid := OS.create_process(OS.get_executable_path(), launch_args)
	if pid <= 0:
		_handle_game_launch_failure("Korsanların Hazinesi başlatılamadı.")
		return
	_track_session("korsanlar", pid)
	_show_toast("Korsanların Hazinesi PARDEX oturumuyla başlatıldı.")


func _handle_game_launch_failure(message: String) -> void:
	_game_launch_in_progress = false
	PardexOnline.report_game_launch_failed()
	_show_toast(message)


func _find_korsan_project_path() -> String:
	var override_path := OS.get_environment("PARDEX_KORSAN_PROJECT").strip_edges()
	if not override_path.is_empty() and FileAccess.file_exists(override_path.path_join("project.godot")):
		return override_path
	var pardex_root := ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
	var parent_dir := pardex_root.get_base_dir()
	for candidate in [
		parent_dir.path_join("Korsanlarin-Hazinesi"),
		parent_dir.path_join("Korsanlarin-Hazinesi-main"),
		parent_dir.path_join("Korsanların Hazinesi"),
	]:
		if FileAccess.file_exists(str(candidate).path_join("project.godot")):
			return str(candidate)
	var directory := DirAccess.open(parent_dir)
	if directory == null:
		return ""
	for entry in directory.get_directories():
		if "korsan" in entry.to_lower() and FileAccess.file_exists(parent_dir.path_join(entry).path_join("project.godot")):
			return parent_dir.path_join(entry)
	return ""


# Playtime: PARDEX remembers when a launched game process ends and adds the
# session length to that game's playtime.
func _track_session(game_id: String, pid: int) -> void:
	_sessions[pid] = {"game": game_id, "started": int(Time.get_unix_time_from_system())}


func _poll_sessions() -> void:
	for pid in _sessions.keys():
		if OS.is_process_running(int(pid)):
			continue
		var session: Dictionary = _sessions[pid]
		_sessions.erase(pid)
		var seconds := int(Time.get_unix_time_from_system()) - int(session["started"])
		Catalog.add_playtime(str(session["game"]), seconds)
		Catalog.add_event("session", "%s oturumu: %s" % [str(Catalog.game(str(session["game"])).get("title", "")), Catalog.hours(seconds)], str(session["game"]))


# ------------------------------------------------------------------ settings

func _prepare_settings() -> void:
	(_settings_content.get_node("ProfilePanel/VBox/ProfileRow/ProfileNameEdit") as LineEdit).text = _display_name
	(_settings_content.get_node("OnlinePanel/VBox/ServerRow/ServerUrlEdit") as LineEdit).text = _server_url
	(_settings_content.get_node("DisplayPanel/VBox/FullscreenOnStart") as CheckButton).set_pressed_no_signal(_start_fullscreen)
	_refresh_display_settings_ui()
	_render_avatar_preview()


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	_display_name = str(config.get_value("profile", "display_name", "Pardus")).strip_edges()
	if _display_name.is_empty():
		_display_name = "Pardus"
	_server_url = str(config.get_value("online", "server_url", DEFAULT_SERVER_URL)).strip_edges()
	if PardexOnline.is_automatic_url(_server_url):
		_server_url = DEFAULT_SERVER_URL
	_start_fullscreen = bool(config.get_value("display", "start_fullscreen", false))
	_saved_window_size = Vector2i(
		maxi(MIN_WINDOW_SIZE.x, int(config.get_value("display", "window_width", DEFAULT_WINDOW_SIZE.x))),
		maxi(MIN_WINDOW_SIZE.y, int(config.get_value("display", "window_height", DEFAULT_WINDOW_SIZE.y)))
	)
	_saved_window_position = Vector2i(
		int(config.get_value("display", "window_x", -1)),
		int(config.get_value("display", "window_y", -1))
	)
	_saved_window_maximized = bool(config.get_value("display", "maximized", false))


func _save_settings(capture_window := true) -> int:
	if capture_window:
		_capture_window_state()
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("profile", "display_name", _display_name)
	config.set_value("online", "server_url", _server_url)
	config.set_value("display", "start_fullscreen", _start_fullscreen)
	config.set_value("display", "window_width", _saved_window_size.x)
	config.set_value("display", "window_height", _saved_window_size.y)
	config.set_value("display", "window_x", _saved_window_position.x)
	config.set_value("display", "window_y", _saved_window_position.y)
	config.set_value("display", "maximized", _saved_window_maximized)
	return config.save(SETTINGS_PATH)


func _save_profile_from_settings() -> void:
	var profile_name_edit := _settings_content.get_node("ProfilePanel/VBox/ProfileRow/ProfileNameEdit") as LineEdit
	var new_name := profile_name_edit.text.strip_edges()
	if new_name.is_empty():
		_show_toast("Görünen ad boş bırakılamaz.")
		return
	_display_name = new_name.left(24)
	profile_name_edit.text = _display_name
	if _save_settings() != OK:
		_show_toast("Profil ayarı kaydedilemedi.")
		return
	_apply_profile()
	PardexOnline.update_display_name(_display_name)
	_show_toast("Profil adı kaydedildi.")


func _save_online_settings_and_connect() -> void:
	var server_url_edit := _settings_content.get_node("OnlinePanel/VBox/ServerRow/ServerUrlEdit") as LineEdit
	var requested_url := server_url_edit.text.strip_edges()
	if PardexOnline.is_automatic_url(requested_url):
		requested_url = DEFAULT_SERVER_URL
	elif not requested_url.begins_with("ws://") and not requested_url.begins_with("wss://"):
		_show_toast("Sunucu adresi ws:// veya wss:// ile başlamalı.")
		return
	_server_url = requested_url
	server_url_edit.text = _server_url
	if _save_settings() != OK:
		_show_toast("Bağlantı ayarı kaydedilemedi.")
		return
	PardexOnline.configure(_server_url, _display_name)
	PardexOnline.reconnect_server()
	_show_toast("PARDEX Online bağlantısı yenileniyor.")


func _apply_profile() -> void:
	profile_name_label.text = _display_name
	if _profile_page != null:
		_profile_page.display_name = _display_name
		_profile_page.refresh()
	_render_presence()


# ------------------------------------------------------------------ window

func _apply_window_preferences() -> void:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	get_window().min_size = Vector2i(mini(MIN_WINDOW_SIZE.x, usable.size.x), mini(MIN_WINDOW_SIZE.y, usable.size.y))
	if _start_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	_restore_windowed_state()


func _restore_windowed_state() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var target_size := Vector2i(mini(_saved_window_size.x, usable.size.x), mini(_saved_window_size.y, usable.size.y))
	target_size.x = maxi(target_size.x, mini(MIN_WINDOW_SIZE.x, usable.size.x))
	target_size.y = maxi(target_size.y, mini(MIN_WINDOW_SIZE.y, usable.size.y))
	DisplayServer.window_set_size(target_size)
	var target_position := _saved_window_position
	if target_position.x < 0 or target_position.y < 0 or not usable.has_point(target_position + Vector2i(40, 40)):
		target_position = usable.position + Vector2i(roundi(float(usable.size.x - target_size.x) / 2.0), roundi(float(usable.size.y - target_size.y) / 2.0))
	DisplayServer.window_set_position(target_position)
	if _saved_window_maximized:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func _capture_window_state() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		_saved_window_size = DisplayServer.window_get_size()
		_saved_window_position = DisplayServer.window_get_position()
		_saved_window_maximized = false
	elif mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		_saved_window_maximized = true


func _window_state_changed() -> bool:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		return _saved_window_maximized or DisplayServer.window_get_size() != _saved_window_size or DisplayServer.window_get_position() != _saved_window_position
	if mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		return not _saved_window_maximized
	return false


func _on_fullscreen_toggled(enabled: bool) -> void:
	if enabled == _start_fullscreen:
		return
	if enabled:
		_capture_window_state()
		_start_fullscreen = true
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		_start_fullscreen = false
		_restore_windowed_state()
	_save_settings(false)
	_refresh_display_settings_ui()


func _refresh_display_settings_ui() -> void:
	var state_label := _settings_content.get_node("DisplayPanel/VBox/State") as Label
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		state_label.text = "●  TAM EKRAN"
	elif mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		state_label.text = "●  BÜYÜTÜLMÜŞ PENCERE"
	else:
		var window_size := DisplayServer.window_get_size()
		state_label.text = "●  PENCERE MODU • %d × %d" % [window_size.x, window_size.y]
	state_label.add_theme_color_override("font_color", UI.GREEN)


func _quit_application() -> void:
	_capture_window_state()
	_save_settings(false)
	get_tree().quit()


func _process(delta: float) -> void:
	_session_poll_elapsed += delta
	if _session_poll_elapsed >= SESSION_POLL_INTERVAL:
		_session_poll_elapsed = 0.0
		if not _sessions.is_empty():
			_poll_sessions()
	if _start_fullscreen:
		return
	_window_state_save_elapsed += delta
	if _window_state_save_elapsed < WINDOW_STATE_SAVE_INTERVAL:
		return
	_window_state_save_elapsed = 0.0
	if _window_state_changed():
		_capture_window_state()
		_save_settings(false)
		if _current_page == "settings":
			_refresh_display_settings_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _current_page == "settings":
		_navigate_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _current_page != "store":
		_navigate("store")
		get_viewport().set_input_as_handled()


func _show_toast(message: String) -> void:
	_toast_revision += 1
	var revision := _toast_revision
	toast_label.text = message
	toast_panel.show()
	get_tree().create_timer(2.8).timeout.connect(func():
		if revision == _toast_revision and is_instance_valid(toast_panel):
			toast_panel.hide()
	)
