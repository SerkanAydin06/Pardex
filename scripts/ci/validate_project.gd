extends SceneTree

const RESOURCES := [
    "res://scenes/main.tscn",
    "res://scenes/ui/window_chrome.tscn",
    "res://scenes/screens/settings.tscn",
    "res://scripts/main.gd",
    "res://scripts/online/pardex_identity_guard.gd",
    "res://scripts/online/pardex_online.gd",
    "res://scripts/online/pardex_online_secure_handoff.gd",
    "res://scripts/online/pardex_game_launcher.gd",
    "res://scripts/online/pardex_notifications.gd",
    "res://scripts/ui/pardex_window_frame.gd",
    "res://scripts/ui/pardex_window_icon_state.gd",
    "res://scripts/ui/pardex_text_fit.gd",
    "res://scripts/ui/pardex_ui.gd",
    "res://scripts/ui/pardex_icons.gd",
    "res://scripts/ui/pardex_button_content.gd",
    "res://scripts/data/pardex_catalog.gd",
    "res://scripts/pages/social_page.gd",
    "res://scripts/pages/store_page.gd",
    "res://scripts/pages/library_page.gd",
    "res://scripts/pages/profile_page.gd",
    "res://scenes/pages/store_page.tscn",
    "res://scenes/pages/library_page.tscn",
    "res://scenes/pages/friends_page.tscn",
    "res://scenes/pages/messages_page.tscn",
    "res://assets/ui/Fütüristik Krom Pardex Hub Logosu.png",
    "res://assets/ui/pardex_hub_app_icon.png",
    "res://scenes/ui/empty_state.tscn",
    "res://scenes/ui/chat_bubble.tscn",
    "res://scenes/ui/conversation_row.tscn",
    "res://scenes/ui/friend_row.tscn",
    "res://scenes/ui/store_featured_card.tscn",
    "res://scenes/ui/store_new_card.tscn",
    "res://scenes/ui/library_game_card.tscn",
    "res://scenes/ui/library_list_row.tscn",
    "res://scenes/ui/notification_row.tscn",
    "res://scenes/pages/profile_page.tscn",
    "res://scenes/pages/settings_page.tscn",
    "res://scripts/screens/account_recovery.gd",
    "res://scripts/ci/boot_smoke.gd",
]

func _initialize() -> void:
    var failed := false
    for resource_path in RESOURCES:
        var resource := ResourceLoader.load(resource_path)
        if resource == null:
            push_error("PARDEX CI: yüklenemedi: %s" % resource_path)
            failed = true
        else:
            print("PARDEX CI OK: %s" % resource_path)
    if failed:
        quit(1)
        return
    print("PARDEX CI: proje kaynakları başarıyla doğrulandı.")
    quit(0)
