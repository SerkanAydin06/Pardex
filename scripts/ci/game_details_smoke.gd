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
	var action := detail.get_node("%ActionButton") as Button
	expect(action.get_theme_stylebox("normal") != action.get_theme_stylebox("pressed"), "distinct primary press feedback")
	expect(action.get_theme_stylebox("focus") is StyleBoxFlat and not (action.get_theme_stylebox("focus") as StyleBoxFlat).draw_center, "focus ring preserves button content")
	action.grab_focus()
	expect(action.has_focus(), "primary action accepts keyboard focus")
	action.release_focus()

	expect(detail.get_node("%About").text == entry.long_description, "catalog description")
	expect(detail.get_node("%Gallery").visible, "downloaded screenshot")
	detail.set_operation(true, "İndiriliyor… %25")
	expect(detail.get_node("%ActionButton").disabled, "busy action disabled")
	detail.set_operation(false, "")
	detail.back_requested.emit()
	expect(pages.get_node("StorePage").visible, "return to store")
	main.call("_navigate", "library")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	pages.get_node("LibraryPage").call("_on_details_input", click, "detail_fixture")
	expect(pages.get_node("LibraryPage").visible, "single click leaves library open")
	click.double_click = true
	pages.get_node("LibraryPage").call("_on_details_input", click, "detail_fixture")
	expect(detail.visible, "double click opens details")
	detail.back_requested.emit()
	expect(pages.get_node("LibraryPage").visible, "return to library")
	main.call("_open_game_details", "detail_fixture")
	root.mode = Window.MODE_WINDOWED
	for width in [1366, 1024]:
		root.size = Vector2i(width, 768)
		main.size = Vector2(width, 768)
		main.call("_apply_responsive_layout")
		await create_timer(0.4).timeout
		expect(detail.get_node("%ImageCount").size.y <= 44, "gallery counter stays on one line")
		expect(detail.get_node("%Scroll").get_h_scroll_bar().max_value <= detail.get_node("%Scroll").size.x + 2, "no horizontal overflow")
		await RenderingServer.frame_post_draw
		var output := OS.get_environment("PARDEX_VISUAL_OUTPUT")
		if not output.is_empty():
			root.get_texture().get_image().save_png(output.path_join("detail-%d.png" % width))
	detail.get_node("%EnlargeButton").pressed.emit()
	await process_frame
	expect(detail.get_node("%ImageDialog").visible and detail.get_node("%LargeImage").texture != null, "enlarge screenshot")
	detail.get_node("%ImageDialog").hide()
	detail.get_node("%Scroll").scroll_vertical = 100000
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("PARDEX_VISUAL_OUTPUT")
	if not output.is_empty():
		root.get_texture().get_image().save_png(output.path_join("detail-bottom.png"))
	detail.show_game("vex")
	expect(detail.get_node("%ActionButton").disabled and not detail.get_node("%Gallery").visible, "upcoming game and empty gallery")
	# Render an installed card and list row; the regular library reference is empty.
	var folder := ProjectSettings.globalize_path(D.ROOT.path_join("detail_fixture").path_join("fixture"))
	DirAccess.make_dir_recursive_absolute(folder)
	var executable := FileAccess.open(folder.path_join("Game.exe"), FileAccess.WRITE)
	executable.store_string("visual fixture")
	executable.close()
	var installed := ConfigFile.new()
	installed.set_value("detail_fixture", "package", {"version": entry.version, "sha256": entry.package.sha256, "path": "fixture/Game.exe"})
	installed.save(D.INSTALLED)
	main.call("_navigate", "library")
	var library := pages.get_node("LibraryPage")
	library.refresh()
	for width in [1366, 1024]:
		root.size = Vector2i(width, 768)
		main.size = Vector2(width, 768)
		main.call("_apply_responsive_layout")
		for list_view in [false, true]:
			library.call("_set_view", list_view)
			await create_timer(0.3).timeout
			var grid: GridContainer = library.get("_grid")
			expect(grid.get_child_count() == 1, "installed fixture in library")
			var card := grid.get_child(0)
			var play_path := "Row/PlayButton" if list_view else "Column/InfoMargin/Info/Bottom/PlayButton"
			expect(card.get_node(play_path).text == "Oyna", "direct play action")
			expect(card.get_node(play_path).get_global_rect().end.x <= library.get_global_rect().end.x, "play action fits")
			await RenderingServer.frame_post_draw
			if not output.is_empty():
				root.get_texture().get_image().save_png(output.path_join("library-actions-%d-%s.png" % [width, "list" if list_view else "grid"]))
	D.uninstall("detail_fixture")
	D.manifest = saved
	if failures == 0:
		print("GAME DETAILS PASSED: routing, metadata, gallery, action state and responsive layout")
	quit(0 if failures == 0 else 1)
