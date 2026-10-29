extends Node

# The main scene intentionally keeps its editor workflow for sibling Godot
# projects. This autoload handles exported PARDEX builds, where the launcher
# must start a packaged game executable instead.
signal game_process_started(game_id: String, pid: int)

const KORSAN_GAME_ID := "korsanlar"
const KORSAN_EXECUTABLE_ENV := "PARDEX_KORSAN_EXECUTABLE"


func _ready() -> void:
	if not PardexOnline.game_start_requested.is_connected(_on_game_start_requested):
		PardexOnline.game_start_requested.connect(_on_game_start_requested)


func _on_game_start_requested(payload: Dictionary) -> void:
	# In the editor, scripts/main.gd keeps the established sibling-project flow.
	if OS.has_feature("editor"):
		return
	var game_id := str(payload.get("game_id", "")).strip_edges()
	if game_id not in [KORSAN_GAME_ID, "hukum"]:
		return

	var main_scene := get_tree().current_scene
	if main_scene != null and main_scene.get("_updater") != null and main_scene.get("_updater").busy():
		_claim_launch(main_scene)
		PardexOnline.report_game_launch_failed()
		_show_toast(main_scene, "Devam eden kurulumun bitmesini bekle.")
		return
	var executable_path := find_game_executable(game_id)
	if executable_path.is_empty():
		_claim_launch(main_scene)
		PardexOnline.report_game_launch_failed()
		_show_toast(
			main_scene,
			"Oyun yüklü değil. Kütüphaneden oyunu indir; indirme görünmüyorsa oyun paketi henüz yayınlanmamıştır."
		)
		return

	var launch_args := PardexOnline.build_game_launch_args(game_id)
	if launch_args.is_empty():
		_claim_launch(main_scene)
		PardexOnline.report_game_launch_failed()
		_show_toast(main_scene, "PARDEX güvenli oyun bileti hazırlanamadı; oyun başlatılmadı.")
		return

	var pid := OS.create_process(executable_path, exported_process_args(launch_args))
	_claim_launch(main_scene)
	if pid <= 0:
		PardexOnline.report_game_launch_failed()
		_show_toast(main_scene, "Oyun paketi başlatılamadı.")
		return

	game_process_started.emit(game_id, pid)
	_show_toast(main_scene, "Oyun PARDEX oturumuyla başlatıldı.")


func exported_process_args(user_args: PackedStringArray) -> PackedStringArray:
	# Exported Godot games also read get_cmdline_user_args(), after the separator.
	var args := PackedStringArray(["--"])
	args.append_array(user_args)
	return args


func _find_korsan_executable() -> String:
	var managed := preload("res://scripts/data/pardex_distribution.gd").executable(KORSAN_GAME_ID)
	if not managed.is_empty():
		return managed
	var override_path := OS.get_environment(KORSAN_EXECUTABLE_ENV).strip_edges()
	if not override_path.is_empty() and FileAccess.file_exists(override_path):
		return override_path

	var launcher_dir := OS.get_executable_path().get_base_dir()
	var candidates := [
		launcher_dir.path_join("games/korsanlar/KorsanlarinHazinesi.exe"),
		launcher_dir.path_join("games/KorsanlarinHazinesi.exe"),
		launcher_dir.path_join("KorsanlarinHazinesi.exe"),
		launcher_dir.path_join("Korsanlarin-Hazinesi/KorsanlarinHazinesi.exe"),
	]
	for candidate_value in candidates:
		var candidate := str(candidate_value)
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func _claim_launch(main_scene: Node) -> void:
	# main.gd receives the same signal after this autoload. Mark the launch as
	# handled so it does not run the editor-only fallback or report twice.
	if main_scene != null:
		main_scene.set("_game_launch_in_progress", true)


func _show_toast(main_scene: Node, message: String) -> void:
	if main_scene != null and main_scene.has_method("_show_toast"):
		main_scene.call("_show_toast", message)


func find_game_executable(game_id: String) -> String:
	if game_id == KORSAN_GAME_ID:
		return _find_korsan_executable()
	if game_id != "hukum":
		return ""
	var managed := preload("res://scripts/data/pardex_distribution.gd").executable(game_id)
	if not managed.is_empty():
		return managed
	var override_path := OS.get_environment("PARDEX_HUKUM_EXECUTABLE").strip_edges()
	if not override_path.is_empty() and FileAccess.file_exists(override_path):
		return override_path
	var base := OS.get_executable_path().get_base_dir()
	for candidate in ["games/hukum/Hukum.exe", "games/hukum/Hukum.x86_64", "games/hukum/Hukum", "Hukum.exe", "Hukum.x86_64"]:
		var full_path := base.path_join(candidate)
		if FileAccess.file_exists(full_path):
			return full_path
	return ""
