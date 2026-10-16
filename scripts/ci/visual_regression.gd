extends SceneTree

# Visual regression: renders every launcher page at 1366x768 (offline, no
# live data) and compares a downscaled copy with tests/visual/<page>.png.
# Run with a real display (xvfb-run in CI). PARDEX_VISUAL_UPDATE=1 rewrites
# the references after an intended design change.

const REFERENCE_DIR := "res://tests/visual"
const WINDOW_SIZE := Vector2i(1366, 768)
const COMPARE_SIZE := Vector2i(456, 256)
# A pixel "changed" when a channel moves more than this (0..1).
const PIXEL_THRESHOLD := 0.12
# Allowed share of changed pixels: animated logo glow and font hinting noise.
const MAX_CHANGED_RATIO := 0.03
const PAGES := ["StorePage", "LibraryPage", "FriendsPage", "MessagesPage", "ProfilePage", "SettingsPage"]


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("PARDEX visual regression: %s" % message)
	quit(1)


func _run() -> void:
	var update := OS.get_environment("PARDEX_VISUAL_UPDATE") == "1"
	var output_dir := OS.get_environment("PARDEX_VISUAL_OUTPUT")
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	root.get_node("PardexOnline").call("disconnect_server")
	root.mode = Window.MODE_WINDOWED
	root.size = WINDOW_SIZE
	scene.size = Vector2(WINDOW_SIZE)
	var preview := scene.get_node("EditorPreview")
	var failures: PackedStringArray = []
	for index in PAGES.size():
		preview.set("preview_page", index)
		preview.call("_show_preview_page")
		scene.call("_apply_responsive_layout")
		for _frame in 3:
			await process_frame
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.convert(Image.FORMAT_RGB8)
		shot.resize(COMPARE_SIZE.x, COMPARE_SIZE.y, Image.INTERPOLATE_BILINEAR)
		var page: String = PAGES[index]
		var reference_path := ProjectSettings.globalize_path(REFERENCE_DIR.path_join(page.to_snake_case() + ".png"))
		if not output_dir.is_empty():
			shot.save_png(output_dir.path_join(page.to_snake_case() + ".png"))
		if update:
			DirAccess.make_dir_recursive_absolute(reference_path.get_base_dir())
			if shot.save_png(reference_path) != OK:
				_fail("could not write %s" % reference_path)
				return
			continue
		var reference := Image.load_from_file(reference_path)
		if reference == null:
			failures.append("%s: reference missing (run with PARDEX_VISUAL_UPDATE=1)" % page)
			continue
		reference.convert(Image.FORMAT_RGB8)
		var ratio := _changed_ratio(shot, reference)
		print("PARDEX visual %s: %.2f%% changed" % [page, ratio * 100.0])
		if ratio > MAX_CHANGED_RATIO:
			failures.append("%s: %.1f%% of pixels changed" % [page, ratio * 100.0])
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		_fail("; ".join(failures))
		return
	print("PARDEX visual regression %s: %d pages at %dx%d" % ["references updated" if update else "passed", PAGES.size(), WINDOW_SIZE.x, WINDOW_SIZE.y])
	quit(0)


func _changed_ratio(a: Image, b: Image) -> float:
	if a.get_size() != b.get_size():
		return 1.0
	var changed := 0
	for y in a.get_height():
		for x in a.get_width():
			var left := a.get_pixel(x, y)
			var right := b.get_pixel(x, y)
			if maxf(absf(left.r - right.r), maxf(absf(left.g - right.g), absf(left.b - right.b))) > PIXEL_THRESHOLD:
				changed += 1
	return float(changed) / float(a.get_width() * a.get_height())
