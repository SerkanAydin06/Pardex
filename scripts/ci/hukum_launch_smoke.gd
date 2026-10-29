extends SceneTree

func _initialize(): call_deferred("run")

func run():
	var launcher = root.get_node("PardexGameLauncher")
	var old_exe = OS.get_environment("PARDEX_HUKUM_EXECUTABLE")
	var old_project = OS.get_environment("PARDEX_HUKUM_PROJECT")
	var fixture = ProjectSettings.globalize_path("user://ci-hukum-project")
	DirAccess.make_dir_recursive_absolute(fixture)
	var file = FileAccess.open(fixture.path_join("project.godot"), FileAccess.WRITE)
	file.store_string("config_version=5\n")
	file.close()
	var exe = fixture.path_join("Hukum-test")
	file = FileAccess.open(exe, FileAccess.WRITE)
	file.store_string("test fixture, never executed")
	file.close()
	OS.set_environment("PARDEX_HUKUM_EXECUTABLE", exe)
	OS.set_environment("PARDEX_HUKUM_PROJECT", fixture)
	var main = load("res://scripts/main.gd").new()
	var passed = launcher.find_game_executable("hukum") == exe and main._find_game_project_path("hukum") == fixture
	passed = passed and launcher.find_game_executable("unknown").is_empty()
	var bridge = load("res://scripts/online/pardex_online_secure_handoff.gd").new()
	bridge.current_room = {"code": "ABCDE", "game_id": "hukum", "match_id": "ci-match", "host_id": "ci-user", "game_server_url": "ws://127.0.0.1:8766"}
	bridge.user_id = "ci-user"
	bridge._secure_game_start_payload = {"game_id": "hukum", "match_id": "ci-match", "launch_ticket": "test-only-one-use"}
	passed = passed and bridge.build_game_launch_args("korsanlar").is_empty()
	var args = bridge.build_game_launch_args("hukum")
	passed = passed and "--pardex-match=ci-match" in args and "--pardex-ticket=test-only-one-use" in args
	passed = passed and bridge.build_game_launch_args("hukum").is_empty()
	bridge.free()
	main.free()
	OS.set_environment("PARDEX_HUKUM_EXECUTABLE", old_exe)
	OS.set_environment("PARDEX_HUKUM_PROJECT", old_project)
	DirAccess.remove_absolute(exe)
	DirAccess.remove_absolute(fixture.path_join("project.godot"))
	DirAccess.remove_absolute(fixture)
	if not passed: push_error("HÜKÜM launcher selection or one-use handoff failed")
	print("PARDEX HUKUM LAUNCH: " + ("PASS" if passed else "FAIL"))
	quit(0 if passed else 1)
