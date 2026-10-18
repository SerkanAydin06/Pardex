extends Control

# PARDEX shell: top bar, sidebar navigation (Mağaza, Kütüphane, Arkadaşlar,
# Profil), page switching, settings, window state, game launch and playtime.
# Each page is its own script under scripts/pages/ and talks back through
# navigate / play_requested / toast signals.

const BugReport := preload("res://scripts/online/pardex_bug_report.gd")
const DesktopNotify := preload("res://scripts/ui/pardex_desktop_notify.gd")
const Distribution := preload("res://scripts/data/pardex_distribution.gd")
const Updater := preload("res://scripts/online/pardex_updater.gd")
const APP_VERSION := "0.2.2"
const SETTINGS_PATH := "user://pardex.cfg"
const DEFAULT_SERVER_URL := ""
const MIN_WINDOW_SIZE := Vector2i(1024, 640)
const SESSION_POLL_INTERVAL := 5.0
const UI := preload("res://scripts/ui/pardex_ui.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")

const WINDOW_NARROW := 1280
const NAV := {
	"StoreButton": ["store", "store"],
	"LibraryButton": ["library", "library"],
	"FriendsButton": ["friends", "friends"],
	"MessagesButton": ["messages", "message"],
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
var _messages_page: VBoxContainer
var _desktop: DesktopNotify
var _install_game_id := ""
var _uninstall_game_id := ""
var _existing_version_button: Button
var _updater: Updater
var _settings_content: VBoxContainer
var _presence_menu: PopupMenu
var _current_page := ""
var _previous_page := "store"
@onready var _avatar_dialog: FileDialog = %AvatarFileDialog
# Page name -> the node shown for it.
var _pages: Dictionary = {}
var _display_name := "Pardus"
var _server_url := DEFAULT_SERVER_URL
var _game_launch_in_progress := false
var _selected_launch_game := ""
var _toast_revision := 0
# pid -> {"game": id, "started": unix} for games PARDEX launched.
var _sessions: Dictionary = {}
var _session_poll_elapsed := 0.0


func _ready() -> void:
	if theme == null:
		theme = UI.app_theme()
	_bind_search()
	_load_settings()
	_apply_start_window()
	_create_pages()
	UI.refine_typography(self)
	_wire_navigation()
	_desktop = DesktopNotify.new()
	add_child(_desktop)
	_wire_updater()
	_wire_online_signals()
	%GameModeDialog.get_node("Options/Official").pressed.connect(_launch_official_game)
	%GameModeDialog.get_node("Options/Private").pressed.connect(_launch_private_game)
	PardexOnline.welcome_received.connect(_on_profile_name_accepted)
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

func _bind_search() -> void:
	# Editable in scenes/main.tscn; runtime only connects its behavior.
	search_field = %LibrarySearch
	search_field.text_changed.connect(_on_search_changed)


func _create_pages() -> void:
	_store_page = _bind_page("store", "StorePage")
	_library_page = _bind_page("library", "LibraryPage")
	_social_page = _bind_page("friends", "FriendsPage")
	_profile_page = _bind_page("profile", "ProfilePage")
	_messages_page = _bind_page("messages", "MessagesPage")
	_bind_page("settings", "SettingsPage")
	_settings_content = %Pages.get_node("SettingsPage/%SettingsContent") as VBoxContainer
	_bind_settings_page()
	if _social_page.has_signal("message_requested"):
		_social_page.message_requested.connect(_open_conversation)
	if _library_page.has_signal("uninstall_requested"):
		_library_page.uninstall_requested.connect(_confirm_uninstall)
	for page in [_store_page, _library_page, _social_page, _profile_page, _messages_page]:
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
	(_settings_content.get_node("SupportPanel/VBox/VersionLabel") as Label).text = "PARDEX sürüm %s" % APP_VERSION
	(_settings_content.get_node("ProfilePanel/VBox/ProfileRow/SaveProfileButton") as Button).pressed.connect(_save_profile_from_settings)
	(_settings_content.get_node("OnlinePanel/VBox/ServerRow/ConnectButton") as Button).pressed.connect(_save_online_settings_and_connect)
	var settings_page := _pages["settings"] as Control
	(settings_page.get_node("%BackButton") as Button).pressed.connect(_navigate_back)
	(settings_page.get_node("%ChooseAvatarButton") as Button).pressed.connect(_choose_avatar)
	(settings_page.get_node("%RemoveAvatarButton") as Button).pressed.connect(func():
		PardexOnline.clear_avatar()
		_show_toast("Profil resmi kaldırıldı.")
	)
	PardexOnline.avatar_ready.connect(func(_account_id): _render_avatar_preview())
	(_settings_content.get_node("SupportPanel/VBox/ReportRow/ReportButton") as Button).pressed.connect(_send_bug_report)


func _send_bug_report() -> void:
	var edit := _settings_content.get_node("SupportPanel/VBox/ReportRow/ReportEdit") as LineEdit
	var state := _settings_content.get_node("SupportPanel/VBox/ReportState") as Label
	if edit.text.strip_edges().is_empty():
		state.text = "Önce sorunu kısaca yaz."
		return
	var report := BugReport.build(edit.text)
	if str(report["version"]).is_empty():
		report["version"] = APP_VERSION
	if PardexOnline.is_online():
		PardexOnline.send_bug_report(report)
		state.text = "Rapor gönderildi. Teşekkürler!"
	else:
		var path := BugReport.save_to_desktop(report)
		state.text = ("Çevrimdışısın; rapor kaydedildi: %s" % path) if not path.is_empty() else "Rapor kaydedilemedi."
	edit.clear()


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
	if not _avatar_dialog.file_selected.is_connected(_on_avatar_selected):
		_avatar_dialog.file_selected.connect(_on_avatar_selected)
	_avatar_dialog.popup_centered_ratio(0.6)


func _on_avatar_selected(path: String) -> void:
	var error := PardexOnline.set_avatar_from_file(path)
	_show_toast(error if not error.is_empty() else "Profil resmi güncellendi.")

func _wire_navigation() -> void:
	for button_name in NAV:
		var button := get_node("%" + button_name) as Button
		var spec: Array = NAV[button_name]
		button.pressed.connect(_navigate.bind(str(spec[0])))
		button.expand_icon = false
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.custom_minimum_size.y = 62
		button.add_theme_font_size_override("font_size", 19)
		button.add_theme_constant_override("icon_max_width", 26)
		button.add_theme_constant_override("h_separation", 20)
	var settings := %SettingsButton as Button
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
# their own query; pages without searchable content hide the entire slot.
const SEARCH_PLACEHOLDERS := {
	"store": "Mağazada oyun, tür ara...",
	"library": "Kütüphanende ara...",
	"friends": "Arkadaş ya da PARDEX kullanıcısı ara...",
}
var _search_queries := {"store": "", "library": "", "friends": ""}


func _update_search_for_page() -> void:
	var searchable := SEARCH_PLACEHOLDERS.has(_current_page)
	(%SearchSlot as Control).visible = searchable
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
	elif _current_page == "friends":
		_social_page.set_query(query)
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
	%Brand.custom_minimum_size.x = sidebar_width - 12.0
	# The approved PARDEX HUB artwork includes the shield, wordmark and HUB.
	# Scale the single transparent image as a unit; never rebuild the mark in UI text.
	%BrandHeader.custom_minimum_size.x = sidebar_width
	(%Brand.get_node("Logo") as Control).custom_minimum_size = Vector2(202 if narrow else 220, 70)
	%Brand.add_theme_constant_override("separation", 0)
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
	for page in [_store_page, _library_page, _social_page, _profile_page, _messages_page]:
		page.apply_layout(content_width)

# ------------------------------------------------------------------ presence

func _build_presence_menu() -> void:
	_presence_menu = %PresenceMenu
	_presence_menu.clear()
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
	PardexOnline.game_session_ready.connect(_on_game_session_ready)
	PardexOnline.social_state_changed.connect(func(_state): _render_unread_badge())
	PardexOnline.chat_message_received.connect(_on_chat_message)
	PardexOnline.room_invite_received.connect(func(invite: Dictionary):
		(%InviteSound as AudioStreamPlayer).play()
		_desktop.notify("%s seni masaya davet ediyor" % str(invite.get("from_display_name", "Bir arkadaşın")))
	)
	PardexOnline.room_state_changed.connect(func(room: Dictionary):
		if not bool(room.get("launching", false)):
			_game_launch_in_progress = false
		if str(room.get("state", "")) == "ended":
			_leave_finished_match()
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


# ------------------------------------------------------------------ updates

func _wire_updater() -> void:
	_updater = Updater.new()
	add_child(_updater)
	var dialog := %UpdateDialog as ConfirmationDialog
	_updater.update_available.connect(func(version: String):
		dialog.dialog_text = "PARDEX %s hazır (şu an %s). Güncelleme indirilip kurulur, PARDEX kendiliğinden yeniden açılır." % [version, APP_VERSION]
		dialog.popup_centered()
	)
	_updater.update_failed.connect(_show_toast)
	_updater.progress.connect(_show_toast)
	_updater.catalog_changed.connect(func():
		for page in _pages.values():
			if page.has_method("refresh"):
				page.refresh()
			elif page.has_method("_render_shelves"):
				page.call("_render_shelves")
	)
	_updater.game_installed.connect(func(id: String): _show_toast("%s hazır. Oyna düğmesiyle başlatabilirsin." % str(Catalog.game(id).get("title", id))))
	_updater.game_uninstalled.connect(func(id: String): _show_toast("%s kaldırıldı." % str(Catalog.game(id).get("title", id))))
	(%UninstallDialog as ConfirmationDialog).confirmed.connect(func():
		if _is_game_running(_uninstall_game_id):
			_show_toast("Kaldırmadan önce oyunu kapat.")
			return
		_updater.uninstall_game(_uninstall_game_id)
	)
	var install_dialog := %GameInstallDialog as ConfirmationDialog
	_existing_version_button = install_dialog.add_button("Mevcut Sürümle Oyna", false, "play_existing")
	_existing_version_button.name = "PlayExisting"
	install_dialog.custom_action.connect(func(action: StringName):
		if action == &"play_existing" and Catalog.is_installed(_install_game_id):
			install_dialog.hide()
			_play_game(_install_game_id, true)
	)
	(%GameInstallDialog as ConfirmationDialog).confirmed.connect(func():
		if not _is_game_running(_install_game_id):
			_updater.install_game(_install_game_id)
	)
	var timer := Timer.new()
	timer.wait_time = 900.0
	timer.autostart = true
	timer.timeout.connect(func(): _updater.check(APP_VERSION))
	add_child(timer)
	dialog.confirmed.connect(func():
		if not _sessions.is_empty():
			_show_toast("PARDEX güncellemesi için açık oyunları kapat.")
			return
		_show_toast("Güncelleme indiriliyor…")
		_updater.install()
	)
	_updater.check(APP_VERSION)


# ------------------------------------------------------------------ messages

func _open_conversation(account_id: String) -> void:
	_navigate("messages")
	_messages_page.call("open_conversation", account_id)


func _render_unread_badge() -> void:
	var unread := PardexOnline.unread_chat_total()
	var badge := %MessagesBadge as PanelContainer
	badge.visible = unread > 0
	badge.add_theme_stylebox_override("panel", UI.box(UI.ACCENT, 12))
	(%MessagesBadgeCount as Label).text = str(mini(unread, 99))
	(%MessagesBadgeCount as Label).add_theme_color_override("font_color", UI.BG)
	_desktop.set_unread(unread)


# A message from a friend while another page is open shows a short toast;
# with PARDEX in the background the taskbar entry flashes too.
func _on_chat_message(with_account_id: String, message: Dictionary, _client_id: String) -> void:
	if str(message.get("from", "")) == PardexOnline.account_id:
		return
	var sender := "Arkadaşın"
	var friends = PardexOnline.social_state.get("friends", [])
	if typeof(friends) == TYPE_ARRAY:
		for profile in friends:
			if typeof(profile) == TYPE_DICTIONARY and str(profile.get("account_id", "")) == with_account_id:
				sender = str(profile.get("display_name", sender))
	var text := str(message.get("text", "")).replace("\n", " ")
	var line := "%s: %s" % [sender, text.left(60) + ("…" if text.length() > 60 else "")]
	(%MessageSound as AudioStreamPlayer).play()
	_desktop.notify(line)
	if _current_page != "messages":
		_show_toast(line)


# ------------------------------------------------------------------ games

func _confirm_uninstall(game_id: String) -> void:
	if _is_game_running(game_id):
		_show_toast("Kaldırmadan önce oyunu kapat.")
		return
	_uninstall_game_id = game_id
	var dialog := %UninstallDialog as ConfirmationDialog
	dialog.dialog_text = "%s bu bilgisayardan kaldırılsın mı? İstediğinde mağazadan tekrar indirebilirsin." % str(Catalog.game(game_id).get("title", "Oyun"))
	dialog.popup_centered()


func _play_game(game_id: String, skip_update := false) -> void:
	var entry := Catalog.game(game_id)
	if entry.is_empty() or not bool(entry["playable"]):
		_show_toast("%s çok yakında PARDEX'te." % str(entry.get("title", "Bu oyun")))
		return
	# PARDEX only opens the game at its own menu. Tables are hosted and joined
	# by code inside the game (PARDEX ONLINE); friends join with "Katıl".
	if _is_game_running(game_id):
		_show_toast("%s zaten açık." % str(entry["title"]))
		return
	if _updater.busy():
		_show_toast("Devam eden kurulumun bitmesini bekle.")
		return
	if not skip_update and Distribution.needs_install(game_id):
		_install_game_id = game_id
		var remote := Distribution.game(game_id)
		var dialog := %GameInstallDialog as ConfirmationDialog
		_existing_version_button.visible = Catalog.is_installed(game_id)
		dialog.dialog_text = "%s %s (%d MB) indirilsin mi? Kayıtların korunur." % [entry["title"], remote["version"], int(float(remote["package"]["size"]) / 1048576.0)]
		dialog.popup_centered()
		return
	if game_id != "korsanlar":
		var executable := Distribution.executable(game_id)
		if not executable.is_empty():
			var pid := OS.create_process(executable, PackedStringArray())
			if pid > 0:
				_track_session(game_id, pid)
			else:
				_show_toast("Oyun başlatılamadı.")
		return
	_selected_launch_game = game_id
	(%GameModeDialog as AcceptDialog).popup_centered(Vector2i(440, 250))


func _launch_official_game() -> void:
	%GameModeDialog.hide()
	if not PardexOnline.is_online():
		_show_toast("Resmî sunucu kapalı. Özel Sunucu seçeneğiyle oynayabilirsin.")
		return
	PardexOnline.request_game_session(_selected_launch_game)
	_show_toast("Oyun resmî sunucu bağlantısıyla açılıyor…")


func _launch_private_game() -> void:
	%GameModeDialog.hide()
	_launch_game_menu(_selected_launch_game, PackedStringArray(["--private-game"]), true)


func _on_game_session_ready(game_id: String, token: String) -> void:
	if game_id != "korsanlar" or token.is_empty() or _is_game_running(game_id):
		return
	var args := PackedStringArray([
		"--pardex-session-token=%s" % token,
		"--pardex-url=%s" % PardexOnline.get_active_server_url(),
		"--pardex-name=%s" % PardexOnline.display_name,
	])
	_launch_game_menu(game_id, args)


func _launch_game_menu(game_id: String, args: PackedStringArray, private_session := false) -> void:
	if game_id != "korsanlar" or _is_game_running(game_id) or _updater.busy():
		return
	var pid := 0
	if OS.has_feature("editor") and Distribution.executable(game_id).is_empty():
		var project_path := _find_korsan_project_path()
		if project_path.is_empty():
			_show_toast("Korsanların Hazinesi geliştirme projesi PARDEX'in yan klasöründe bulunamadı.")
			return
		var launch_args := PackedStringArray(["--path", project_path, "--"])
		launch_args.append_array(args)
		pid = OS.create_process(OS.get_executable_path(), launch_args)
	else:
		var executable_path := str(PardexGameLauncher.call("_find_korsan_executable"))
		if executable_path.is_empty():
			_show_toast("Korsanların Hazinesi yüklü değil. Kütüphaneden oyunu indir; indirme görünmüyorsa oyun paketi henüz yayınlanmamıştır.")
			return
		pid = OS.create_process(executable_path, PardexGameLauncher.exported_process_args(args))
	if pid <= 0:
		_show_toast("Korsanların Hazinesi başlatılamadı.")
		return
	_track_session(game_id, pid, not private_session)


func _on_game_start_requested(payload: Dictionary) -> void:
	var game_id := str(payload.get("game_id", ""))
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
func _track_session(game_id: String, pid: int, record_activity := true) -> void:
	if pid <= 0 or _sessions.has(pid):
		return
	var now := int(Time.get_unix_time_from_system())
	_sessions[pid] = {"game": game_id, "started": now, "saved_at": now, "record_activity": record_activity}
	if record_activity:
		Catalog.record_launch(game_id)


func _save_session_playtime(session: Dictionary, now: int) -> void:
	if not bool(session.get("record_activity", true)):
		return
	var saved_at := int(session["saved_at"])
	if now <= saved_at:
		return
	Catalog.add_playtime(str(session["game"]), now - saved_at)
	session["saved_at"] = now


func _exit_tree() -> void:
	var now := int(Time.get_unix_time_from_system())
	for session in _sessions.values():
		_save_session_playtime(session, now)


func _is_game_running(game_id: String) -> bool:
	for pid in _sessions.keys():
		if str(_sessions[pid]["game"]) == game_id and OS.is_process_running(int(pid)):
			return true
	return false


# Closing the game leaves its match while the in-game lobby is still open or
# once it has ended. A started match keeps the seat (a bot plays it) so "Oyna"
# can take it back.
func _leave_finished_match() -> void:
	var room := PardexOnline.current_room
	if not bool(room.get("quick_play", false)) or _is_game_running(str(room.get("game_id", ""))):
		return
	if str(room.get("state", "")) == "ended" or not bool(room.get("match_started", false)):
		PardexOnline.leave_room()


func _poll_sessions() -> void:
	var now := int(Time.get_unix_time_from_system())
	for pid in _sessions.keys():
		var session: Dictionary = _sessions[pid]
		if OS.is_process_running(int(pid)):
			if now - int(session["saved_at"]) >= 60:
				_save_session_playtime(session, now)
			continue
		_save_session_playtime(session, now)
		_sessions.erase(pid)
		if not bool(session.get("record_activity", true)):
			continue
		if str(session["game"]) == "korsanlar":
			_leave_finished_match()
		var seconds := maxi(0, now - int(session["started"]))
		Catalog.add_event("session", "%s oturumu: %s" % [str(Catalog.game(str(session["game"])).get("title", "")), Catalog.hours(seconds)], str(session["game"]))


# ------------------------------------------------------------------ settings

func _prepare_settings() -> void:
	(_settings_content.get_node("ProfilePanel/VBox/ProfileRow/ProfileNameEdit") as LineEdit).text = _display_name
	(_settings_content.get_node("OnlinePanel/VBox/ServerRow/ServerUrlEdit") as LineEdit).text = _server_url
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


func _save_settings() -> int:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("profile", "display_name", _display_name)
	config.set_value("online", "server_url", _server_url)
	# Window size/position are no longer remembered (see _fit_window_to_screen).
	if config.has_section("display"):
		config.erase_section("display")
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


func _on_profile_name_accepted(_user_id: String, accepted_name: String) -> void:
	if _display_name == accepted_name:
		return
	_display_name = accepted_name
	_save_settings()
	(_settings_content.get_node("ProfilePanel/VBox/ProfileRow/ProfileNameEdit") as LineEdit).text = _display_name
	_apply_profile()


func _apply_profile() -> void:
	profile_name_label.text = _display_name
	if _profile_page != null:
		_profile_page.display_name = _display_name
		_profile_page.refresh()
	_render_presence()


# ------------------------------------------------------------------ window

# The window is never remembered. project.godot decides how PARDEX opens
# (window/size/mode=3: full screen); otherwise, and when leaving full screen
# with the top-right button, it is a window of about 85 % of the usable screen,
# centred (scripts/ui/pardex_window_frame.gd).
func _apply_start_window() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		get_window().min_size = Vector2i(mini(MIN_WINDOW_SIZE.x, usable.size.x), mini(MIN_WINDOW_SIZE.y, usable.size.y))
		return
	_fit_window_to_screen()


func _fit_window_to_screen() -> void:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	get_window().min_size = Vector2i(mini(MIN_WINDOW_SIZE.x, usable.size.x), mini(MIN_WINDOW_SIZE.y, usable.size.y))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_set_fitted_rect(usable)


func _set_fitted_rect(usable: Rect2i) -> void:
	var target_size := Vector2i(roundi(usable.size.x * 0.85), roundi(usable.size.y * 0.85))
	target_size = target_size.clamp(get_window().min_size, usable.size)
	var target_position := usable.position + Vector2i((Vector2(usable.size - target_size) / 2.0).round())
	DisplayServer.window_set_size(target_size)
	DisplayServer.window_set_position(target_position)
	# Windows can still apply the creation size right after start-up; set the
	# rect again a frame later so it sticks (and Godot's cached size matches).
	await get_tree().process_frame
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(target_size)
		DisplayServer.window_set_position(target_position)


func _quit_application() -> void:
	_save_settings()
	get_tree().quit()


func _process(delta: float) -> void:
	_session_poll_elapsed += delta
	if _session_poll_elapsed >= SESSION_POLL_INTERVAL:
		_session_poll_elapsed = 0.0
		if not _sessions.is_empty():
			_poll_sessions()


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
