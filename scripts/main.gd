extends Control

const APP_VERSION := "0.1.0"
const SETTINGS_PATH := "user://pardex.cfg"
const DEFAULT_SERVER_URL := "wss://pardex-online-production.up.railway.app"
const DEFAULT_WINDOW_SIZE := Vector2i(1440, 900)
const MIN_WINDOW_SIZE := Vector2i(1100, 700)
const WINDOW_STATE_SAVE_INTERVAL := 1.0
const FRIENDS_SCENE := preload("res://scenes/screens/friends.tscn")
const ROOMS_SCENE := preload("res://scenes/screens/rooms.tscn")
const SETTINGS_SCENE := preload("res://scenes/screens/settings.tscn")

@onready var page_title: Label = %PageTitle
@onready var page_subtitle: Label = %PageSubtitle
@onready var library_content: VBoxContainer = %LibraryContent
@onready var toast_panel: PanelContainer = %ToastPanel
@onready var toast_label: Label = %ToastLabel
@onready var version_label: Label = %VersionLabel
@onready var profile_name_label: Label = $Sidebar/SidebarMargin/SidebarVBox/ProfilePanel/ProfileRow/ProfileText/UserName
@onready var avatar_label: Label = $Sidebar/SidebarMargin/SidebarVBox/ProfilePanel/ProfileRow/Avatar
@onready var online_state_label: Label = $Sidebar/SidebarMargin/SidebarVBox/ProfilePanel/ProfileRow/ProfileText/OnlineState
@onready var connection_label: Label = $MainMargin/MainVBox/Header/ConnectionPill/ConnectionLabel

var _friends_content: VBoxContainer
var _rooms_content: VBoxContainer
var _rooms_scroll: ScrollContainer
var _settings_content: VBoxContainer
var _current_content: Control
var _display_name := "Pardus"
var _server_url := DEFAULT_SERVER_URL
var _nav_selected_style: StyleBox
var _nav_normal_style: StyleBox
var _game_launch_in_progress := false
var _toast_revision := 0
var _start_fullscreen := false
var _saved_window_size := DEFAULT_WINDOW_SIZE
var _saved_window_position := Vector2i(-1, -1)
var _saved_window_maximized := false
var _window_state_save_elapsed := 0.0

func _ready() -> void:
    version_label.text = "PARDEX v%s" % APP_VERSION
    _nav_selected_style = %LibraryButton.get_theme_stylebox("normal")
    _nav_normal_style = %FriendsButton.get_theme_stylebox("normal")

    _create_secondary_screens()
    _load_settings()
    _apply_window_preferences()
    _apply_profile()
    _prepare_game_cards()
    _wire_actions()
    _wire_online_signals()
    _show_library()
    _render_empty_room()
    _update_connection_ui(PardexOnline.connection_state)
    toast_panel.hide()

    PardexOnline.configure(_server_url, _display_name)
    PardexOnline.connect_server()

func _create_secondary_screens() -> void:
    var content_parent := library_content.get_parent()

    _friends_content = FRIENDS_SCENE.instantiate() as VBoxContainer
    content_parent.add_child(_friends_content)
    _friends_content.hide()

    # Rooms can be taller than the available launcher area. Keep the shared
    # page header fixed and scroll only the room content instead of allowing
    # its minimum height to push the header out of alignment.
    _rooms_scroll = ScrollContainer.new()
    _rooms_scroll.name = "RoomsScroll"
    _rooms_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _rooms_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _rooms_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    content_parent.add_child(_rooms_scroll)

    _rooms_content = ROOMS_SCENE.instantiate() as VBoxContainer
    _rooms_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _rooms_scroll.add_child(_rooms_content)
    _rooms_scroll.hide()

    _settings_content = SETTINGS_SCENE.instantiate() as VBoxContainer
    content_parent.add_child(_settings_content)
    _settings_content.hide()

func _wire_actions() -> void:
    %LibraryButton.pressed.connect(_show_library)
    %FriendsButton.pressed.connect(_show_friends)
    %RoomsButton.pressed.connect(_show_rooms)
    %SettingsButton.pressed.connect(_show_settings)
    %ExitButton.pressed.connect(_quit_application)

    var create_room_button := _rooms_content.get_node("Actions/CreateCard/VBox/CreateRoomButton") as Button
    var room_code_edit := _rooms_content.get_node("Actions/JoinCard/VBox/RoomCode") as LineEdit
    var join_room_button := _rooms_content.get_node("Actions/JoinCard/VBox/JoinRoomButton") as Button
    var ready_button := _rooms_content.get_node("CurrentRoom/VBox/RoomActions/ReadyButton") as Button
    var start_game_button := _rooms_content.get_node("CurrentRoom/VBox/RoomActions/StartGameButton") as Button
    var leave_room_button := _rooms_content.get_node("CurrentRoom/VBox/RoomActions/LeaveRoomButton") as Button

    create_room_button.pressed.connect(func(): PardexOnline.create_room("korsanlar", 4))
    join_room_button.pressed.connect(func(): PardexOnline.join_room(room_code_edit.text))
    room_code_edit.text_submitted.connect(func(_value: String): PardexOnline.join_room(room_code_edit.text))
    ready_button.pressed.connect(_toggle_ready)
    start_game_button.pressed.connect(PardexOnline.request_start_game)
    leave_room_button.pressed.connect(PardexOnline.leave_room)

    var save_profile_button := _settings_content.get_node("ProfilePanel/VBox/ProfileRow/SaveProfileButton") as Button
    var connect_button := _settings_content.get_node("OnlinePanel/VBox/ServerRow/ConnectButton") as Button
    var fullscreen_toggle := _settings_content.get_node("DisplayPanel/VBox/FullscreenOnStart") as CheckButton
    save_profile_button.pressed.connect(_save_profile_from_settings)
    connect_button.pressed.connect(_save_online_settings_and_connect)
    fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)

func _wire_online_signals() -> void:
    PardexOnline.connection_state_changed.connect(_update_connection_ui)
    PardexOnline.room_state_changed.connect(_render_room)
    PardexOnline.room_left.connect(_render_empty_room)
    PardexOnline.online_error.connect(_show_toast)
    PardexOnline.game_start_requested.connect(_on_game_start_requested)

func _prepare_game_cards() -> void:
    _set_game_card(
        %VexStatus,
        %VexPath,
        %VexPlayButton,
        "GELİŞTİRİLİYOR",
        "Windows sürümü oyun tamamlanınca hazırlanacak"
    )
    _set_game_card(
        %KorsanStatus,
        %KorsanPath,
        %KorsanPlayButton,
        "PARDEX ONLINE BAĞLI",
        "Online oda ve dedicated oyun sunucusu hazır"
    )
    _set_game_card(
        %FirtinaStatus,
        %FirtinaPath,
        %FirtinaPlayButton,
        "GELİŞTİRİLİYOR",
        "Windows sürümü oyun tamamlanınca hazırlanacak"
    )

func _set_game_card(
    status_label: Label,
    detail_label: Label,
    action_button: Button,
    status_text: String,
    detail_text: String
) -> void:
    status_label.text = status_text
    status_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.32, 1))
    detail_label.text = detail_text
    action_button.text = "GELİŞTİRİLİYOR"
    action_button.disabled = true

func _show_library() -> void:
    _show_content(
        library_content,
        "Kütüphane",
        "Tüm oyunların tek merkezde.",
        %LibraryButton
    )

func _show_friends() -> void:
    _show_content(
        _friends_content,
        "Arkadaşlar",
        "Arkadaşlarını bul, durumlarını gör ve oyunlara davet et.",
        %FriendsButton
    )

func _show_rooms() -> void:
    _show_content(
        _rooms_scroll,
        "Odalar",
        "Ortak oyun oturumlarını buradan yönet.",
        %RoomsButton
    )

func _show_settings() -> void:
    var profile_name_edit := _settings_content.get_node("ProfilePanel/VBox/ProfileRow/ProfileNameEdit") as LineEdit
    var server_url_edit := _settings_content.get_node("OnlinePanel/VBox/ServerRow/ServerUrlEdit") as LineEdit
    profile_name_edit.text = _display_name
    server_url_edit.text = _server_url
    var fullscreen_toggle := _settings_content.get_node("DisplayPanel/VBox/FullscreenOnStart") as CheckButton
    fullscreen_toggle.set_pressed_no_signal(_start_fullscreen)
    _refresh_display_settings_ui()
    _show_content(
        _settings_content,
        "Ayarlar",
        "PARDEX profilini ve bağlantı ayarlarını yönet.",
        %SettingsButton
    )

func _show_content(content: Control, title: String, subtitle: String, selected_button: Button) -> void:
    library_content.hide()
    _friends_content.hide()
    _rooms_scroll.hide()
    _settings_content.hide()

    content.show()
    _current_content = content
    page_title.text = title
    page_subtitle.text = subtitle
    _set_selected_navigation(selected_button)

func _set_selected_navigation(selected_button: Button) -> void:
    var buttons := [%LibraryButton, %FriendsButton, %RoomsButton, %SettingsButton]
    for node in buttons:
        var button := node as Button
        button.add_theme_stylebox_override("normal", _nav_normal_style)
        button.add_theme_color_override("font_color", Color(0.65, 0.7, 0.79, 1))

    selected_button.add_theme_stylebox_override("normal", _nav_selected_style)
    selected_button.add_theme_color_override("font_color", Color(0.91, 0.94, 1, 1))

func _load_settings() -> void:
    var config := ConfigFile.new()
    if config.load(SETTINGS_PATH) != OK:
        return

    _display_name = str(config.get_value("profile", "display_name", "Pardus")).strip_edges()
    if _display_name.is_empty():
        _display_name = "Pardus"

    _server_url = str(config.get_value("online", "server_url", DEFAULT_SERVER_URL)).strip_edges()
    if _server_url.is_empty() or _server_url == "ws://127.0.0.1:8765":
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


func _apply_window_preferences() -> void:
    get_window().min_size = MIN_WINDOW_SIZE
    if _start_fullscreen:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
        return
    _restore_windowed_state()


func _restore_windowed_state() -> void:
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

    var screen := DisplayServer.window_get_current_screen()
    var usable := DisplayServer.screen_get_usable_rect(screen)
    var target_size := Vector2i(
        mini(_saved_window_size.x, usable.size.x),
        mini(_saved_window_size.y, usable.size.y)
    )
    target_size.x = maxi(target_size.x, mini(MIN_WINDOW_SIZE.x, usable.size.x))
    target_size.y = maxi(target_size.y, mini(MIN_WINDOW_SIZE.y, usable.size.y))
    DisplayServer.window_set_size(target_size)

    var target_position := _saved_window_position
    var probe_position := target_position + Vector2i(40, 40)
    if target_position.x < 0 or target_position.y < 0 or not usable.has_point(probe_position):
        var offset_x := roundi(float(usable.size.x - target_size.x) / 2.0)
        var offset_y := roundi(float(usable.size.y - target_size.y) / 2.0)
        target_position = usable.position + Vector2i(offset_x, offset_y)
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
        return (
            _saved_window_maximized
            or DisplayServer.window_get_size() != _saved_window_size
            or DisplayServer.window_get_position() != _saved_window_position
        )
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
    if _settings_content == null:
        return

    var state_label := _settings_content.get_node("DisplayPanel/VBox/State") as Label
    var mode := DisplayServer.window_get_mode()
    if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
        state_label.text = "●  TAM EKRAN"
    elif mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
        state_label.text = "●  BÜYÜTÜLMÜŞ PENCERE"
    else:
        var window_size := DisplayServer.window_get_size()
        state_label.text = "●  PENCERE MODU • %d × %d" % [window_size.x, window_size.y]
    state_label.add_theme_color_override("font_color", Color(0.38, 0.86, 0.62, 1))


func _quit_application() -> void:
    _capture_window_state()
    _save_settings(false)
    get_tree().quit()

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
    if requested_url.is_empty():
        requested_url = DEFAULT_SERVER_URL
    if not requested_url.begins_with("ws://") and not requested_url.begins_with("wss://"):
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
    avatar_label.text = _display_name.left(1).to_upper()

func _update_connection_ui(state: String) -> void:
    var settings_state_label := _settings_content.get_node("OnlinePanel/VBox/State") as Label
    var create_room_button := _rooms_content.get_node("Actions/CreateCard/VBox/CreateRoomButton") as Button
    var join_room_button := _rooms_content.get_node("Actions/JoinCard/VBox/JoinRoomButton") as Button

    var text := "●  ÇEVRİMDIŞI"
    var color := Color(0.9, 0.42, 0.42, 1)
    if state == "connecting":
        text = "●  BAĞLANIYOR"
        color = Color(0.9, 0.7, 0.32, 1)
    elif state == "online":
        text = "●  ÇEVRİMİÇİ"
        color = Color(0.38, 0.86, 0.62, 1)

    connection_label.text = text
    connection_label.add_theme_color_override("font_color", color)
    online_state_label.text = text
    online_state_label.add_theme_color_override("font_color", color)
    settings_state_label.text = text
    settings_state_label.add_theme_color_override("font_color", color)

    var online := state == "online"
    create_room_button.disabled = not online
    join_room_button.disabled = not online

func _toggle_ready() -> void:
    if PardexOnline.current_room.is_empty():
        return

    var self_is_ready := false
    var members: Array = PardexOnline.current_room.get("members", [])
    for member_data in members:
        if typeof(member_data) != TYPE_DICTIONARY:
            continue
        var member: Dictionary = member_data
        if str(member.get("user_id", "")) == PardexOnline.user_id:
            self_is_ready = bool(member.get("ready", false))
            break

    PardexOnline.set_ready(not self_is_ready)

func _render_room(room: Dictionary) -> void:
    var room_code_label := _rooms_content.get_node("CurrentRoom/VBox/Header/CurrentRoomCode") as Label
    var room_summary := _rooms_content.get_node("CurrentRoom/VBox/RoomSummary") as Label
    var launch_hint := _rooms_content.get_node("CurrentRoom/VBox/LaunchHint") as Label
    var members_box := _rooms_content.get_node("CurrentRoom/VBox/MembersVBox") as VBoxContainer
    var ready_button := _rooms_content.get_node("CurrentRoom/VBox/RoomActions/ReadyButton") as Button
    var start_game_button := _rooms_content.get_node("CurrentRoom/VBox/RoomActions/StartGameButton") as Button
    var leave_room_button := _rooms_content.get_node("CurrentRoom/VBox/RoomActions/LeaveRoomButton") as Button

    room_code_label.text = str(room.get("code", "—"))
    var members: Array = room.get("members", [])
    var max_players := int(room.get("max_players", 4))
    var game_name := "Korsanların Hazinesi" if str(room.get("game_id", "")) == "korsanlar" else str(room.get("game_id", "Oyun"))
    room_summary.text = "%s  •  %d/%d oyuncu" % [game_name, members.size(), max_players]

    for child in members_box.get_children():
        child.queue_free()

    var self_is_ready := false
    var all_ready := members.size() >= 2
    var host_id := str(room.get("host_id", ""))
    for member_data in members:
        if typeof(member_data) != TYPE_DICTIONARY:
            continue
        var member: Dictionary = member_data
        var member_id := str(member.get("user_id", ""))
        var member_name := str(member.get("display_name", "Oyuncu"))
        var member_ready := bool(member.get("ready", false))
        all_ready = all_ready and member_ready

        var row := HBoxContainer.new()
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

        var name_label := Label.new()
        name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        name_label.text = member_name + ("  ★ Kurucu" if member_id == host_id else "")
        name_label.add_theme_font_size_override("font_size", 15)
        name_label.add_theme_color_override("font_color", Color(0.88, 0.92, 0.98, 1))
        row.add_child(name_label)

        var state_label := Label.new()
        state_label.custom_minimum_size = Vector2(82, 0)
        state_label.text = "HAZIR" if member_ready else "BEKLİYOR"
        state_label.add_theme_font_size_override("font_size", 13)
        state_label.add_theme_color_override(
            "font_color",
            Color(0.38, 0.86, 0.62, 1) if member_ready else Color(0.58, 0.63, 0.72, 1)
        )
        state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        row.add_child(state_label)
        members_box.add_child(row)

        if member_id == PardexOnline.user_id:
            self_is_ready = member_ready

    var is_host := host_id == PardexOnline.user_id
    var has_game_server := str(room.get("game_server_url", "")).begins_with("ws")
    var launching := bool(room.get("launching", false))

    ready_button.disabled = launching
    leave_room_button.disabled = false
    ready_button.text = "HAZIRLIĞI KALDIR" if self_is_ready else "HAZIR"

    start_game_button.visible = is_host
    start_game_button.disabled = not (is_host and all_ready and has_game_server and not launching)
    if launching:
        start_game_button.text = "OYUN BAŞLATILIYOR…"
        launch_hint.text = "PARDEX oturumu başlatıldı • Oyuncular oyuna aktarılıyor"
        launch_hint.add_theme_color_override("font_color", Color(0.38, 0.86, 0.62, 1))
    elif not has_game_server:
        start_game_button.text = "SUNUCU BEKLENİYOR"
        launch_hint.text = "Korsan oyun sunucusu henüz atanmadı."
        launch_hint.add_theme_color_override("font_color", Color(0.9, 0.7, 0.32, 1))
    elif members.size() < 2:
        start_game_button.text = "OYUNCU BEKLENİYOR"
        launch_hint.text = "Oyunu başlatmak için en az 2 oyuncu gerekli."
        launch_hint.add_theme_color_override("font_color", Color(0.58, 0.63, 0.72, 1))
    elif not all_ready:
        start_game_button.text = "HERKES HAZIR DEĞİL"
        launch_hint.text = "Tüm oyuncular HAZIR olduğunda kurucu oyunu başlatabilir."
        launch_hint.add_theme_color_override("font_color", Color(0.58, 0.63, 0.72, 1))
    else:
        start_game_button.text = "OYUNU BAŞLAT"
        launch_hint.text = "Tüm oyuncular hazır • Korsan oyun sunucusu bağlı"
        launch_hint.add_theme_color_override("font_color", Color(0.38, 0.86, 0.62, 1))

    if not is_host and not launching:
        launch_hint.text = "Kurucu tüm oyuncular hazır olduğunda oyunu başlatacak."

func _render_empty_room() -> void:
    if _rooms_content == null:
        return

    var room_code_label := _rooms_content.get_node("CurrentRoom/VBox/Header/CurrentRoomCode") as Label
    var room_summary := _rooms_content.get_node("CurrentRoom/VBox/RoomSummary") as Label
    var launch_hint := _rooms_content.get_node("CurrentRoom/VBox/LaunchHint") as Label
    var members_box := _rooms_content.get_node("CurrentRoom/VBox/MembersVBox") as VBoxContainer
    var ready_button := _rooms_content.get_node("CurrentRoom/VBox/RoomActions/ReadyButton") as Button
    var start_game_button := _rooms_content.get_node("CurrentRoom/VBox/RoomActions/StartGameButton") as Button
    var leave_room_button := _rooms_content.get_node("CurrentRoom/VBox/RoomActions/LeaveRoomButton") as Button

    room_code_label.text = "—"
    room_summary.text = "Henüz bir odada değilsin."
    launch_hint.text = "Bir oda oluştur veya oda koduyla arkadaşına katıl."
    launch_hint.add_theme_color_override("font_color", Color(0.44, 0.5, 0.59, 1))
    for child in members_box.get_children():
        child.queue_free()

    var empty_label := Label.new()
    empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    empty_label.text = "Oda oluşturduğunda veya bir odaya katıldığında oyuncular burada görünecek."
    empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    empty_label.add_theme_font_size_override("font_size", 14)
    empty_label.add_theme_color_override("font_color", Color(0.44, 0.5, 0.59, 1))
    members_box.add_child(empty_label)

    ready_button.text = "HAZIR"
    ready_button.disabled = true
    start_game_button.visible = false
    start_game_button.disabled = true
    leave_room_button.disabled = true
    _game_launch_in_progress = false


func _on_game_start_requested(payload: Dictionary) -> void:
    if _game_launch_in_progress:
        return
    if str(payload.get("game_id", "")) != "korsanlar":
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
    var exact_candidates := [
        parent_dir.path_join("Korsanlarin-Hazinesi"),
        parent_dir.path_join("Korsanlarin-Hazinesi-main"),
        parent_dir.path_join("Korsanların Hazinesi"),
    ]
    for candidate in exact_candidates:
        if FileAccess.file_exists(str(candidate).path_join("project.godot")):
            return str(candidate)

    var directory := DirAccess.open(parent_dir)
    if directory == null:
        return ""
    directory.list_dir_begin()
    var entry := directory.get_next()
    while not entry.is_empty():
        if directory.current_is_dir() and "korsan" in entry.to_lower():
            var candidate := parent_dir.path_join(entry)
            if FileAccess.file_exists(candidate.path_join("project.godot")):
                directory.list_dir_end()
                return candidate
        entry = directory.get_next()
    directory.list_dir_end()
    return ""

func _process(delta: float) -> void:
    if _start_fullscreen:
        return

    _window_state_save_elapsed += delta
    if _window_state_save_elapsed < WINDOW_STATE_SAVE_INTERVAL:
        return
    _window_state_save_elapsed = 0.0

    if _window_state_changed():
        _capture_window_state()
        _save_settings(false)
        _refresh_display_settings_ui()


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel") and _current_content != library_content:
        _show_library()
        get_viewport().set_input_as_handled()

func _show_toast(message: String) -> void:
    _toast_revision += 1
    var revision := _toast_revision
    toast_label.text = message
    toast_panel.show()
    var timer := get_tree().create_timer(2.6)
    timer.timeout.connect(func():
        if revision == _toast_revision and is_instance_valid(toast_panel):
            toast_panel.hide()
    )
