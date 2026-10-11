extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Verify the selector's layout logic without loading EditorNode itself.
	# Runtime isolation of the exported setter is checked in boot_smoke.gd.
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	root.get_node("PardexOnline").call("disconnect_server")
	var preview := scene.get_node("EditorPreview")
	var pages := scene.get_node("Root/Body/MainMargin/Pages")
	var names := ["StorePage", "LibraryPage", "FriendsPage", "MessagesPage", "ProfilePage", "SettingsPage"]
	for window_size in [Vector2i(1366, 768), Vector2i(1920, 1080)]:
		root.size = window_size
		for selected in names.size():
			preview.set("preview_page", selected)
			preview.call("_show_preview_page")
			await process_frame
			await process_frame
			for index in names.size():
				var page := pages.get_node(names[index]) as Control
				if page.visible != (index == selected):
					push_error("Editor page switch failed: %s" % names[index])
					quit(1)
					return
			if (pages.get_node(names[selected]) as Control).size.x <= 0:
				push_error("Editor preview has no layout width.")
				quit(1)
				return
	print("PARDEX editor preview passed: six pages at 1366x768 and 1920x1080")
	scene.queue_free()
	await process_frame
	quit(0)
