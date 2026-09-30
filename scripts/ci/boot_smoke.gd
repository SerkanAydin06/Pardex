extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const CI_SERVER_URL := "ws://127.0.0.1:65535"
const IDENTITY_PATH := "user://pardex_identity.cfg"


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("PARDEX boot smoke: %s" % message)
	quit(1)


func _is_valid_identity_key(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _verify_identity_repair(identity_guard: Node) -> bool:
	var broken := ConfigFile.new()
	broken.set_value("identity", "key", "z".repeat(64))
	if broken.save(IDENTITY_PATH) != OK:
		_fail("invalid identity fixture could not be written")
		return false

	identity_guard.call("_ensure_valid_identity")
	var repaired := ConfigFile.new()
	if repaired.load(IDENTITY_PATH) != OK:
		_fail("repaired identity could not be loaded")
		return false
	var repaired_key := str(repaired.get_value("identity", "key", "")).strip_edges().to_lower()
	if not _is_valid_identity_key(repaired_key):
		_fail("identity guard did not repair an invalid key")
		return false
	return true


func _run() -> void:
	var identity_guard := _autoload("PardexIdentityGuard")
	var online := _autoload("PardexOnline")
	var game_launcher := _autoload("PardexGameLauncher")
	if identity_guard == null or online == null or game_launcher == null:
		_fail("required autoloads are missing")
		return
	if not _verify_identity_repair(identity_guard):
		return

	var config := ConfigFile.new()
	config.set_value("profile", "display_name", "CI-Pardus")
	config.set_value("online", "server_url", CI_SERVER_URL)
	if config.save("user://pardex.cfg") != OK:
		_fail("CI settings could not be written")
		return

	online.call("configure", CI_SERVER_URL, "CI-Pardus")

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
		"Root/Header/BrandHeader/BrandMargin/Brand/Logo",
		"Root/Header/ActionHeader/ActionMargin/HeaderRow/WindowChrome",
		"Root/Body/Sidebar/SidebarColumn/NavMargin/NavList/StoreButton",
		"Root/Body/Sidebar/SidebarColumn/NavMargin/NavList/LibraryButton",
		"Root/Body/Sidebar/SidebarColumn/NavMargin/NavList/FriendsButton",
		"Root/Body/Sidebar/SidebarColumn/NavMargin/NavList/ProfileButton",
		"Root/Body/Sidebar/SidebarColumn/ProfilePanel/ProfileRow/SettingsButton",
		"Root/Body/MainMargin/Pages/StorePage",
		"Root/Body/MainMargin/Pages/FriendsPage",
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

	online.call("disconnect_server")
	print("PARDEX boot smoke passed: identity repair -> main scene -> secure launcher autoloads -> dynamic social UI")
	quit(0)
