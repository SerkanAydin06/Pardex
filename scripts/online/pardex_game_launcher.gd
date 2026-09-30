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
	if str(payload.get("game_id", "")).strip_edges() != KORSAN_GAME_ID:
		return

	var main_scene := get_tree().current_scene
	var executable_path := _find_korsan_executable()
	if executable_path.is_empty():
		_claim_launch(main_scene)
		PardexOnline.report_game_launch_failed()
		_show_toast(
			main_scene,
			"Korsanların Hazinesi paketi bulunamadı. games/korsanlar/KorsanlarinHazinesi.exe yolunu kontrol et."
		)
		return

	var launch_args := PardexOnline.build_game_launch_args(KORSAN_GAME_ID)
	if launch_args.is_empty():
		_claim_launch(main_scene)
		PardexOnline.report_game_launch_failed()
		_show_toast(main_scene, "PARDEX güvenli oyun bileti hazırlanamadı; Korsan başlatılmadı.")
		return

	var pid := OS.create_process(executable_path, launch_args)
	_claim_launch(main_scene)
	if pid <= 0:
		PardexOnline.report_game_launch_failed()
		_show_toast(main_scene, "Korsanların Hazinesi paketi başlatılamadı.")
		return

	game_process_started.emit(KORSAN_GAME_ID, pid)
	_show_toast(main_scene, "Korsanların Hazinesi PARDEX oturumuyla başlatıldı.")


func _find_korsan_executable() -> String:
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
