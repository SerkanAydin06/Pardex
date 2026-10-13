extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _capture(effect: ShaderMaterial, enabled: bool, clock: float) -> Image:
	effect.set_shader_parameter("effects_enabled", enabled)
	effect.set_shader_parameter("motion_enabled", true)
	effect.set_shader_parameter("effect_time", clock)
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _run() -> void:
	root.size = Vector2i(720, 260)
	var background := ColorRect.new()
	background.color = Color("080d1a")
	background.size = Vector2(720, 260)
	root.add_child(background)
	var source := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var logo := source.get_node("Root/Body/Sidebar/SidebarColumn/BrandHeader/BrandMargin/Brand/Logo").duplicate() as TextureRect
	source.free()
	logo.animation_enabled = false
	logo.position = Vector2(30, 35)
	logo.size = Vector2(660, 190)
	root.add_child(logo)
	var effect := logo.material as ShaderMaterial
	var plain := await _capture(effect, false, 2.0)
	var glowing := await _capture(effect, true, 2.0)
	var sweep := await _capture(effect, true, 0.9)
	var glow_delta := 0.0
	var sweep_delta := 0.0
	for y in plain.get_height():
		for x in plain.get_width():
			var base := plain.get_pixel(x, y)
			var lit := glowing.get_pixel(x, y)
			var flash := sweep.get_pixel(x, y)
			glow_delta += absf(lit.r - base.r) + absf(lit.g - base.g) + absf(lit.b - base.b)
			sweep_delta += absf(flash.r - lit.r) + absf(flash.g - lit.g) + absf(flash.b - lit.b)
	if glow_delta < 1.0 or sweep_delta < 1.0 or sweep.get_pixel(0, 0) != plain.get_pixel(0, 0):
		push_error("PARDEX logo shader failed: glow/sweep missing or background changed.")
		quit(1)
		return
	var preview_path := OS.get_environment("PARDEX_LOGO_PREVIEW_PATH")
	if not preview_path.is_empty() and sweep.save_png(preview_path) != OK:
		push_error("PARDEX logo preview could not be saved.")
		quit(1)
		return
	print("PARDEX logo render passed: silhouette glow -> chrome sweep -> transparent background")
	logo.queue_free()
	background.queue_free()
	await process_frame
	if not preview_path.is_empty():
		var shell := (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(shell)
		root.get_node("PardexOnline").call("disconnect_server")
		await process_frame
		await process_frame
		for window_size in [Vector2i(1366, 768), Vector2i(1920, 1080)]:
			root.mode = Window.MODE_WINDOWED
			root.size = window_size
			shell.size = Vector2(window_size)
			shell.call("_apply_responsive_layout")
			await process_frame
			await process_frame
			await create_timer(0.25).timeout
			await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			var output := preview_path.get_base_dir().path_join("shell-preview-%d.png" % window_size.x)
			if screenshot.save_png(output) != OK:
				push_error("PARDEX shell preview could not be saved.")
				quit(1)
				return
		shell.queue_free()
		await process_frame
	quit(0)
