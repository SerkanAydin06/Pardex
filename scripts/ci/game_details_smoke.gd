extends SceneTree

const D := preload("res://scripts/data/pardex_distribution.gd")
var failures := 0


func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("Game details: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	root.get_node("PardexOnline").disconnect_server()
	await process_frame
	var saved := D.manifest.duplicate(true)
	var source := "res://assets/ui/top_banner.png"
	var digest := FileAccess.get_sha256(source)
	var asset := {"url": "https://example.invalid/packages/" + digest + ".png", "sha256": digest, "size": FileAccess.get_file_as_bytes(source).size()}
	DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(D.art_download_path(asset)))
	var entry := {"id": "detail_fixture", "title": "Keşif Yolculuğu", "version": "1.2.0", "executable": "Game.exe", "package": {"url": "https://example.invalid/game.zip", "sha256": "a".repeat(64), "size": 100}, "description": "Yeni dünyalar, yeni maceralar.", "long_description": "Oyunun hikâyesi ve özellikleri burada yer alır. Bu içerik yayınlanan katalogdan gelir.", "requirements": "Windows 10 veya üzeri\n4 GB RAM", "release_notes": "1.2.0 — Yeni bölüm eklendi.", "connection_modes": "Tek oyunculu", "genres": ["Macera"], "players": "Tek oyunculu", "screenshots": [asset]}
	D.manifest = {"schema": 1, "launcher": {}, "games": [entry]}
	expect(D.validate(D.manifest), "accept detail metadata")
	var bad := D.manifest.duplicate(true)
	bad.games[0].screenshots = [asset, asset, asset, asset, asset, asset, asset, asset, asset]
	expect(not D.validate(bad), "reject excessive screenshots")
	var pages := main.get_node("%Pages")
	pages.get_node("StorePage").details_requested.emit("detail_fixture")
	var detail := pages.get_node("GameDetailPage")
	expect(detail.visible and detail.game_id == "detail_fixture", "store opens details")
	expect(detail.get_node("%ActionButton").text == "İndir", "uninstalled game action")
	expect(detail.get_node("%About").text == entry.long_description, "catalog description")
	expect(detail.get_node("%Gallery").visible, "downloaded screenshot")
	detail.set_operation(true, "İndiriliyor… %25")
	expect(detail.get_node("%ActionButton").disabled, "busy action disabled")
	detail.set_operation(false, "")
	detail.back_requested.emit()
	expect(pages.get_node("StorePage").visible, "return to store")
	main.call("_navigate", "library")
	pages.get_node("LibraryPage").details_requested.emit("detail_fixture")
	detail.back_requested.emit()
	expect(pages.get_node("LibraryPage").visible, "return to library")
	main.call("_open_game_details", "detail_fixture")
	root.mode = Window.MODE_WINDOWED
	for width in [1366, 1024]:
		root.size = Vector2i(width, 768)
		main.size = Vector2(width, 768)
		main.call("_apply_responsive_layout")
		await create_timer(0.4).timeout
		expect(detail.get_node("%Scroll").get_h_scroll_bar().max_value <= detail.get_node("%Scroll").size.x + 2, "no horizontal overflow")
		await RenderingServer.frame_post_draw
		var output := OS.get_environment("PARDEX_VISUAL_OUTPUT")
		if not output.is_empty():
			root.get_texture().get_image().save_png(output.path_join("detail-%d.png" % width))
	detail.show_game("vex")
	expect(detail.get_node("%ActionButton").disabled and not detail.get_node("%Gallery").visible, "upcoming game and empty gallery")
	D.manifest = saved
	if failures == 0:
		print("GAME DETAILS PASSED: routing, metadata, gallery, action state and responsive layout")
	quit(0 if failures == 0 else 1)
