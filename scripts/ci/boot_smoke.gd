extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const CI_SERVER_URL := "ws://127.0.0.1:65535"


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("PARDEX boot smoke: %s" % message)
	quit(1)


func _run() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "display_name", "CI-Pardus")
	config.set_value("online", "server_url", CI_SERVER_URL)
	if config.save("user://pardex.cfg") != OK:
		_fail("CI settings could not be written")
		return

	PardexOnline.configure(CI_SERVER_URL, "CI-Pardus")

	var packed := ResourceLoader.load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("main scene could not be loaded")
		return

	var main_scene := packed.instantiate()
	if main_scene == null:
		_fail("main scene could not be instantiated")
		return

	root.add_child(main_scene)
	current_scene = main_scene

	await process_frame
	await process_frame
	await process_frame

	var required_paths := [
		"Sidebar/SidebarMargin/SidebarVBox/FriendsButton",
		"Sidebar/SidebarMargin/SidebarVBox/RoomsButton",
		"MainMargin/MainVBox/Header/HeaderRow/ConnectionPill/ConnectionLabel",
	]
	for node_path in required_paths:
		if main_scene.get_node_or_null(node_path) == null:
			_fail("required node missing: %s" % node_path)
			return

	if main_scene.find_child("NotificationButton", true, false) == null:
		_fail("notification button was not created")
		return
	if main_scene.find_child("NotificationCenter", true, false) == null:
		_fail("notification center was not created")
		return
	if main_scene.find_child("OnlineState", true, false) == null:
		_fail("presence label was not found")
		return

	PardexOnline.disconnect_server()
	print("PARDEX boot smoke passed: main scene -> autoloads -> dynamic social UI")
	quit(0)
