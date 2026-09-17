extends Control

const CONFIG_PATH := "user://pardex_games.cfg"
const APP_VERSION := "0.1.0"

@onready var page_title: Label = %PageTitle
@onready var page_subtitle: Label = %PageSubtitle
@onready var toast_panel: PanelContainer = %ToastPanel
@onready var toast_label: Label = %ToastLabel
@onready var version_label: Label = %VersionLabel

var _game_nodes := {}
var _paths := {
    "vex": "",
    "korsanlar": "",
    "firtina": "",
}

var _file_dialog: FileDialog
var _pending_game_id := ""
var _pending_display_name := ""

func _ready() -> void:
    _game_nodes = {
        "vex": {
            "button": %VexPlayButton,
            "status": %VexStatus,
            "path": %VexPath,
        },
        "korsanlar": {
            "button": %KorsanPlayButton,
            "status": %KorsanStatus,
            "path": %KorsanPath,
        },
        "firtina": {
            "button": %FirtinaPlayButton,
            "status": %FirtinaStatus,
            "path": %FirtinaPath,
        },
    }

    version_label.text = "PARDEX v%s" % APP_VERSION
    _create_file_dialog()
    _load_paths()
    _refresh_game_cards()
    _wire_actions()
    toast_panel.hide()

func _wire_actions() -> void:
    %LibraryButton.pressed.connect(_show_library)
    %FriendsButton.pressed.connect(func(): _show_placeholder("Arkadaşlar", "PARDEX Online ile arkadaş listesi burada görünecek."))
    %RoomsButton.pressed.connect(func(): _show_placeholder("Odalar", "Oda oluşturma ve davet sistemi PARDEX Online aşamasında eklenecek."))
    %SettingsButton.pressed.connect(func(): _show_toast("Oyun dosyasını değiştirmek için ilgili karttaki DÜZELT düğmesini kullanabilirsin."))

    %VexPlayButton.pressed.connect(func(): _on_game_button_pressed("vex", "VEX"))
    %KorsanPlayButton.pressed.connect(func(): _on_game_button_pressed("korsanlar", "Korsanların Hazinesi"))
    %FirtinaPlayButton.pressed.connect(func(): _on_game_button_pressed("firtina", "Fırtına Vadisi"))

func _create_file_dialog() -> void:
    _file_dialog = FileDialog.new()
    _file_dialog.title = "Oyun çalıştırılabilir dosyasını seç"
    _file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _file_dialog.filters = PackedStringArray(["*.exe ; Windows uygulaması (*.exe)"])
    _file_dialog.file_selected.connect(_on_executable_selected)
    add_child(_file_dialog)

func _show_library() -> void:
    page_title.text = "Kütüphane"
    page_subtitle.text = "Tüm oyunların tek merkezde."
    %LibraryContent.show()
    _show_toast("Kütüphane hazır.")

func _show_placeholder(title: String, subtitle: String) -> void:
    page_title.text = title
    page_subtitle.text = subtitle
    %LibraryContent.show()
    _show_toast("%s bölümü PARDEX Online aşamasında etkinleşecek." % title)

func _load_paths() -> void:
    var config := ConfigFile.new()
    var err := config.load(CONFIG_PATH)
    if err != OK:
        _save_config()
        return

    for game_id in _paths.keys():
        _paths[game_id] = str(config.get_value("games", game_id, ""))

func _save_config() -> void:
    var config := ConfigFile.new()
    for game_id in _paths.keys():
        config.set_value("games", game_id, str(_paths[game_id]))
    var err := config.save(CONFIG_PATH)
    if err != OK:
        push_warning("PARDEX oyun yolları kaydedilemedi. Hata kodu: %s" % err)

func _refresh_game_cards() -> void:
    for game_id in _game_nodes.keys():
        var executable_path := str(_paths.get(game_id, ""))
        var nodes: Dictionary = _game_nodes[game_id]
        var button: Button = nodes["button"]
        var status: Label = nodes["status"]
        var path_label: Label = nodes["path"]

        if executable_path.is_empty():
            status.text = "BAĞLANTI BEKLİYOR"
            path_label.text = "Oyun dosyası henüz seçilmedi"
            button.text = "BAĞLA"
        elif FileAccess.file_exists(executable_path):
            status.text = "HAZIR"
            path_label.text = executable_path
            button.text = "OYNA"
        else:
            status.text = "DOSYA BULUNAMADI"
            path_label.text = executable_path
            button.text = "DÜZELT"

func _on_game_button_pressed(game_id: String, display_name: String) -> void:
    var executable_path := str(_paths.get(game_id, ""))
    if executable_path.is_empty() or not FileAccess.file_exists(executable_path):
        _choose_executable(game_id, display_name)
        return
    _launch_game(game_id, display_name)

func _choose_executable(game_id: String, display_name: String) -> void:
    _pending_game_id = game_id
    _pending_display_name = display_name
    _file_dialog.title = "%s çalıştırılabilir dosyasını seç" % display_name

    var current_path := str(_paths.get(game_id, ""))
    if not current_path.is_empty():
        var current_dir := current_path.get_base_dir()
        if DirAccess.dir_exists_absolute(current_dir):
            _file_dialog.current_dir = current_dir

    _file_dialog.popup_centered_ratio(0.72)

func _on_executable_selected(path: String) -> void:
    if _pending_game_id.is_empty():
        return

    if path.get_extension().to_lower() != "exe":
        _show_toast("Lütfen Windows için bir .exe dosyası seç.")
        return

    if not FileAccess.file_exists(path):
        _show_toast("Seçilen dosya bulunamadı.")
        return

    _paths[_pending_game_id] = path
    _save_config()
    _refresh_game_cards()
    _show_toast("%s PARDEX'e bağlandı." % _pending_display_name)
    _pending_game_id = ""
    _pending_display_name = ""

func _launch_game(game_id: String, display_name: String) -> void:
    var executable_path := str(_paths.get(game_id, ""))
    if executable_path.is_empty():
        _choose_executable(game_id, display_name)
        return
    if not FileAccess.file_exists(executable_path):
        _choose_executable(game_id, display_name)
        return

    var pid := OS.create_process(executable_path, [])
    if pid <= 0:
        _show_toast("%s başlatılamadı." % display_name)
        return
    _show_toast("%s başlatıldı." % display_name)

func _show_toast(message: String) -> void:
    toast_label.text = message
    toast_panel.show()
    var timer := get_tree().create_timer(3.0)
    timer.timeout.connect(func():
        if is_instance_valid(toast_panel):
            toast_panel.hide()
    )
