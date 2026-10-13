extends SceneTree


func _initialize() -> void:
	var expected := PackedStringArray([
		"--private-game", "--pardex-session-token=ci-only", "--pardex-name=İsim Boşluk",
		"--pardex", "--pardex-ticket=ci-ticket",
	])
	quit(0 if OS.get_cmdline_user_args() == expected else 1)
