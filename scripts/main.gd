extends Control

const APP_VERSION := "0.1.0"
const SETTINGS_PATH := "user://pardex.cfg"
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
@onready var connection_label: Label = $MainMargin/MainVBox/Header/ConnectionPill/ConnectionLabel

var _friends_content: VBoxContainer
var _rooms_content: VBoxContainer
var _settings_content: VBoxContainer
var _current_content: Control
var _display_name := "Pardus"
var _nav_selected_style: StyleBox
var _nav_normal_style: StyleBox

func _ready() -> void:
    version_label.text = "PARDEX v%s" % APP_VERSION
    connection_label.text = "●  GELİŞTİRME MODU"
    connection_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.32, 1))

    _nav_selected_style = %LibraryButton.get_theme_stylebox("normal")
    _nav_normal_style = %FriendsButton.get_theme_stylebox("normal")

    _create_secondary_screens()
    _load_settings()
    _apply_profile()
    _prepare_game_cards()
    _wire_actions()
    _show_library(false)
    toast_panel.hide()

func _create_secondary_screens() -> void:
    var content_parent := library_content.get_parent()

    _friends_content = FRIENDS_SCENE.instantiate()
    content_parent.add_child(_friends_content)
    _friends_content.hide()

    _rooms_content = ROOMS_SCENE.instantiate()
    content_parent.add_child(_rooms_content)
    _rooms_content.hide()

    _settings_content = SETTINGS_SCENE.instantiate()
    content_parent.add_child(_settings_content)
    _settings_content.hide()

func _wire_actions() -> void:
    %LibraryButton.pressed.connect(func(): _show_library(true))
    %FriendsButton.pressed.connect(_show_friends)
    %RoomsButton.pressed.connect(_show_rooms)
    %SettingsButton.pressed.connect(_show_settings)

    var create_room_button: Button = _rooms_content.get_node("Actions/CreateCard/VBox/CreateRoomButton")
    var join_room_button: Button = _rooms_content.get_node("Actions/JoinCard/VBox/JoinRoomButton")
    create_room_button.pressed.connect(func(): _show_toast("Oda oluşturma PARDEX Online sunucusu bağlandığında aktif olacak."))
    join_room_button.pressed.connect(func(): _show_toast("Oda koduyla katılma PARDEX Online sunucusu bağlandığında aktif olacak."))

    var save_profile_button: Button = _settings_content.get_node("ProfilePanel/VBox/ProfileRow/SaveProfileButton")
    save_profile_button.pressed.connect(_save_profile_from_settings)

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
        "ONLINE ENTEGRASYON SIRASINDA",
        "İlk PARDEX Online bağlantısı bu oyunla yapılacak"
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

func _show_library(show_message := true) -> void:
    _show_content(
        library_content,
        "Kütüphane",
        "Tüm oyunların tek merkezde.",
        %LibraryButton
    )
    if show_message:
        _show_toast("Kütüphane")

func _show_friends() -> void:
    _show_content(
        _friends_content,
        "Arkadaşlar",
        "Arkadaşlarını bul, durumlarını gör ve oyunlara davet et.",
        %FriendsButton
    )

func _show_rooms() -> void:
    _show_content(
        _rooms_content,
        "Odalar",
        "Ortak oyun oturumlarını buradan yöneteceksin.",
        %RoomsButton
    )

func _show_settings() -> void:
    var profile_name_edit: LineEdit = _settings_content.get_node("ProfilePanel/VBox/ProfileRow/ProfileNameEdit")
    profile_name_edit.text = _display_name
    _show_content(
        _settings_content,
        "Ayarlar",
        "PARDEX profilini ve uygulama ayarlarını yönet.",
        %SettingsButton
    )

func _show_content(content: Control, title: String, subtitle: String, selected_button: Button) -> void:
    library_content.hide()
    _friends_content.hide()
    _rooms_content.hide()
    _settings_content.hide()

    content.show()
    _current_content = content
    page_title.text = title
    page_subtitle.text = subtitle
    _set_selected_navigation(selected_button)

func _set_selected_navigation(selected_button: Button) -> void:
    var buttons: Array[Button] = [%LibraryButton, %FriendsButton, %RoomsButton, %SettingsButton]
    for button in buttons:
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

func _save_profile_from_settings() -> void:
    var profile_name_edit: LineEdit = _settings_content.get_node("ProfilePanel/VBox/ProfileRow/ProfileNameEdit")
    var new_name := profile_name_edit.text.strip_edges()
    if new_name.is_empty():
        _show_toast("Görünen ad boş bırakılamaz.")
        return

    _display_name = new_name.left(24)
    profile_name_edit.text = _display_name

    var config := ConfigFile.new()
    config.set_value("profile", "display_name", _display_name)
    var error := config.save(SETTINGS_PATH)
    if error != OK:
        _show_toast("Profil ayarı kaydedilemedi.")
        return

    _apply_profile()
    _show_toast("Profil adı kaydedildi.")

func _apply_profile() -> void:
    profile_name_label.text = _display_name
    avatar_label.text = _display_name.left(1).to_upper()

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel") and _current_content != library_content:
        _show_library(false)
        get_viewport().set_input_as_handled()

func _show_toast(message: String) -> void:
    toast_label.text = message
    toast_panel.show()
    var timer := get_tree().create_timer(2.6)
    timer.timeout.connect(func():
        if is_instance_valid(toast_panel):
            toast_panel.hide()
    )
