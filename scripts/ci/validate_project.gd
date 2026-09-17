extends SceneTree

const RESOURCES := [
    "res://scenes/main.tscn",
    "res://scenes/screens/friends.tscn",
    "res://scenes/screens/rooms.tscn",
    "res://scenes/screens/settings.tscn",
    "res://scripts/main.gd",
    "res://scripts/online/pardex_online.gd",
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
