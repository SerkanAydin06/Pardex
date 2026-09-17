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
    _load_paths()
    _refresh_game_cards()
    _wire_actions()
    toast_panel.hide()

func _wire_actions() -> void:
    %LibraryButton.pressed.connect(_show_library)
    %FriendsButton.pressed.connect(func(): _show_placeholder("Arkadaşlar", "PARDEX Online ile arkadaş listesi burada görünecek."))
    %RoomsButton.pressed.connect(func(): _show_placeholder("Odalar", "Oda oluşturma ve davet sistemi PARDEX Online aşamasında eklenecek."))
    %SettingsButton.pressed.connect(func(): _show_toast("Oyun yollarını şimdilik user://pardex_games.cfg dosyasından düzenleyebilirsin."))

    %VexPlayButton.pressed.connect(func(): _launch_game("vex", "VEX"))
    %KorsanPlayButton.pressed.connect(func(): _launch_game("korsanlar", "Korsanların Hazinesi"))
    %FirtinaPlayButton.pressed.connect(func(): _launch_game("firtina", "Fırtına Vadisi"))

func _show_library() -> void:
    page_title.text = "Kütüphane"
    page_subtitle.text = "Tüm oyunların tek merkezde."
    %LibraryContent.show()
    _show_toast("Kütüphane hazır.")

func _show_placeholder(title: String, subtitle: String) -> void:
    page_title.text = title
    page_subtitle.text = subtitle
    %LibraryContent.show()
    _show_toast("%s bölümü sonraki PARDEX Online aşamasında etkinleşecek." % title)

func _load_paths() -> void:
    var config := ConfigFile.new()
    var err := config.load(CONFIG_PATH)
    if err != OK:
        _save_default_config(config)
        return

    for game_id in _paths.keys():
        _paths[game_id] = str(config.get_value("games", game_id, ""))

func _save_default_config(config: ConfigFile) -> void:
    for game_id in _paths.keys():
        config.set_value("games", game_id, "")
    config.save(CONFIG_PATH)

func _refresh_game_cards() -> void:
    for game_id in _game_nodes.keys():
        var executable_path := str(_paths.get(game_id, ""))
        var nodes: Dictionary = _game_nodes[game_id]
        var button: Button = nodes["button"]
        var status: Label = nodes["status"]
        var path_label: Label = nodes["path"]

        if executable_path.is_empty():
            status.text = "BAĞLANTI BEKLİYOR"
            path_label.text = "Oyun yolu henüz tanımlanmadı"
            button.text = "BAĞLA"
        elif FileAccess.file_exists(executable_path):
            status.text = "HAZIR"
            path_label.text = executable_path
            button.text = "OYNA"
        else:
            status.text = "DOSYA BULUNAMADI"
            path_label.text = executable_path
            button.text = "DÜZELT"

func _launch_game(game_id: String, display_name: String) -> void:
    var executable_path := str(_paths.get(game_id, ""))
    if executable_path.is_empty():
        _show_toast("%s henüz PARDEX'e bağlanmadı." % display_name)
        return
    if not FileAccess.file_exists(executable_path):
        _show_toast("%s çalıştırılabilir dosyası bulunamadı." % display_name)
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
