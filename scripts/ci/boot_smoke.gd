extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const CI_SERVER_URL := "ws://127.0.0.1:65535"
const IDENTITY_PATH := "user://pardex_identity.cfg"
const Catalog := preload("res://scripts/data/pardex_catalog.gd")


class RetryProbe:
	extends "res://scripts/online/pardex_online_secure_handoff.gd"
	var address_checks := 0

	func _resolve_address() -> void:
		# Exercise the real resolver's status changes, then supply a deterministic
		# closed-host result without contacting GitHub or waiting on HTTP.
		address_checks += 1
		super._resolve_address()
		_address_request.cancel_request()
		_on_address_resolved(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"online":""}'.to_utf8_buffer())


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


func _effective_texture_filter(item: CanvasItem) -> int:
	var ancestor: Node = item
	while ancestor != null:
		if ancestor is CanvasItem and (ancestor as CanvasItem).texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
			return (ancestor as CanvasItem).texture_filter
		ancestor = ancestor.get_parent()
	return CanvasItem.TEXTURE_FILTER_LINEAR


func _verify_texture_filters(node: Node) -> bool:
	if node is CanvasItem:
		var filter := _effective_texture_filter(node as CanvasItem)
		if filter not in [CanvasItem.TEXTURE_FILTER_LINEAR, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS]:
			_fail("non-smooth UI filtering at %s" % node.get_path())
			return false
		if node is TextureRect and (node as TextureRect).texture != null:
			var path := (node as TextureRect).texture.resource_path
			if path.ends_with(".svg") and filter != CanvasItem.TEXTURE_FILTER_LINEAR:
				_fail("small vector icon must use linear filtering: %s" % node.get_path())
				return false
			if path.ends_with(".png") and filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
				_fail("scaled artwork must use mipmaps: %s" % node.get_path())
				return false
	for child in node.get_children():
		if not _verify_texture_filters(child):
			return false
	return true


func _verify_quiet_retries() -> bool:
	var board_url := OS.get_environment("PARDEX_ADDRESS_BOARD_URL")
	OS.set_environment("PARDEX_ADDRESS_BOARD_URL", "http://127.0.0.1:65534")
	var probe := RetryProbe.new()
	root.add_child(probe)
	probe.set_process(false)
	probe.configure("", "CI-Retry")
	probe._host_closed_reported = true
	var states: Array[String] = []
	probe.connection_state_changed.connect(func(state: String): states.append(state))
	for _cycle in 3:
		probe._address_age = INF
		probe._process(probe.RECONNECT_DELAY)
	var quiet := states.is_empty() and probe.address_checks == 3 and probe.is_host_closed()
	probe._address_age = INF
	probe.connect_server()
	var explicit_connect := states == ["connecting", "offline"]
	states.clear()
	probe.configure("ws://127.0.0.1:65533", "CI-Retry")
	probe.connect_server(true)
	quiet = quiet and states.is_empty() and probe.connection_state == "offline"
	probe._socket.close()
	probe._process(0.0)
	probe._socket = null
	probe.connect_server()
	explicit_connect = explicit_connect and probe.connection_state == "connecting"
	probe._socket.close()
	probe._process(0.0)
	probe._handle_packet('{"type":"welcome","user_id":"ci-user","account_id":"px_ci","display_name":"CI-Retry","social_enabled":false}')
	var welcomed := probe.connection_state == "online" and probe._session_ready
	probe.free()
	if board_url.is_empty():
		OS.unset_environment("PARDEX_ADDRESS_BOARD_URL")
	else:
		OS.set_environment("PARDEX_ADDRESS_BOARD_URL", board_url)
	if not quiet or not explicit_connect or not welcomed:
		_fail("offline retries flickered, explicit connection was hidden, or welcome was ignored")
		return false
	return true


func _verify_activity_and_chat(main_scene: Node, online: Node) -> bool:
	var before := Catalog.games_with_stats()[0] as Dictionary
	main_scene.call("_track_session", "korsanlar", -1)
	if int(Catalog.games_with_stats()[0]["launches"]) != int(before["launches"]):
		_fail("failed process launch changed activity")
		return false
	var test_pid := 2147483647
	main_scene.call("_track_session", "korsanlar", test_pid)
	main_scene.call("_track_session", "korsanlar", test_pid)
	if int(Catalog.games_with_stats()[0]["launches"]) != int(before["launches"]) + 1:
		_fail("successful process must be recorded exactly once")
		return false
	var sessions: Dictionary = main_scene.get("_sessions")
	var now := int(Time.get_unix_time_from_system())
	sessions[test_pid]["started"] = now - 120
	sessions[test_pid]["saved_at"] = now - 120
	# A checkpoint followed by shutdown must preserve time without doubling it.
	main_scene.call("_save_session_playtime", sessions[test_pid], now)
	main_scene.call("_exit_tree")
	var added := int(Catalog.games_with_stats()[0]["playtime"]) - int(before["playtime"])
	if added < 120 or added > 121:
		_fail("checkpoint/shutdown lost or duplicated playtime")
		return false
	sessions.clear()
	# No mode question: without PARDEX Online the game opens for private play.
	if main_scene.get_node_or_null("GameModeDialog") != null or main_scene.call("play_mode") != "private":
		_fail("offline play must open private mode directly")
		return false
	var private_before := Catalog.games_with_stats()[0] as Dictionary
	main_scene.call("_track_session", "korsanlar", test_pid + 1, false)
	main_scene.call("_save_session_playtime", sessions[test_pid + 1], now + 120)
	var private_after := Catalog.games_with_stats()[0] as Dictionary
	if int(private_before["launches"]) != int(private_after["launches"]) or int(private_before["playtime"]) != int(private_after["playtime"]):
		_fail("private game updated PARDEX profile activity")
		return false
	sessions.clear()
	var messages := main_scene.find_child("MessagesPage", true, false)
	var histories: Dictionary = messages.get("_histories")
	histories["stale_conversation"] = [{"text": "cached before disconnect"}]
	online.emit_signal("welcome_received", "ci-user", "CI-Pardus_2")
	var name_edit := main_scene.find_child("ProfileNameEdit", true, false) as LineEdit
	var settings := ConfigFile.new()
	settings.load("user://pardex.cfg")
	if main_scene.get("_display_name") != "CI-Pardus_2" or name_edit.text != "CI-Pardus_2" or str(settings.get_value("profile", "display_name", "")) != "CI-Pardus_2":
		_fail("server accepted name did not update profile/settings UI")
		return false
	if not histories.is_empty():
		_fail("reconnect retained stale chat history")
		return false
	return true


func _verify_scene_owned_ui(main_scene: Node) -> bool:
	var pages := main_scene.get_node("Root/Body/ContentColumn/MainMargin/Pages")
	var library := pages.get_node("LibraryPage")
	var profile := pages.get_node("ProfilePage")
	var library_stats: Node = library.get("_stats_row")
	var profile_stats: Node = profile.get("_stats_row")
	var account: Node = profile.get("_account_list")
	var quick: Node = library.get("_quick_list")
	var preserved := [library_stats.get_child(0), profile_stats.get_child(0), account.get_child(0), quick.get_child(0)]
	var caption := library_stats.get_node("CatalogStat/Row/Text/Caption") as Label
	caption.text = "CI editor caption"
	for index in 3:
		library.call("refresh")
		profile.call("refresh")
	if library_stats.get_child(0) != preserved[0] or profile_stats.get_child(0) != preserved[1] or account.get_child(0) != preserved[2] or quick.get_child(0) != preserved[3]:
		_fail("refresh replaced editor-owned UI nodes")
		return false
	if caption.text != "CI editor caption":
		_fail("refresh overwrote an editor-owned caption")
		return false
	var play := quick.get_node("Quick_korsanlar/Play") as Button
	if play.pressed.get_connections().size() != 1:
		_fail("quick launch has duplicated action connections")
		return false
	var preview := main_scene.get_node("EditorPreview")
	main_scene.call("_navigate", "library")
	preview.set("preview_page", 4)
	if not (library as Control).visible or (profile as Control).visible:
		_fail("editor preview changed runtime navigation")
		return false
	main_scene.call("_navigate", "store")
	return true


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
	var updater := load("res://scripts/online/pardex_updater.gd")
	if not updater.is_newer("v0.1.10", "0.1.9") or updater.is_newer("0.1.0", "0.1.0") \
			or updater.is_newer("0.9", "1.0.0") or not updater.is_newer("1.0.1", "1.0"):
		_fail("update version comparison is wrong")
		return
	# Exercise a real child process: engine args must not swallow game credentials.
	var child_args := PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://scripts/ci/launch_args_probe.gd",
	])
	child_args.append_array(game_launcher.exported_process_args(PackedStringArray([
		"--private-game", "--pardex-session-token=ci-only", "--pardex-name=İsim Boşluk",
		"--pardex", "--pardex-ticket=ci-ticket",
	])))
	var child_output: Array = []
	if OS.execute(OS.get_executable_path(), child_args, child_output, true) != 0:
		_fail("child game did not receive official/private launch arguments")
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
		"Root/Body/Sidebar/SidebarColumn/BrandHeader/BrandMargin/Brand/Logo",
		"Root/Body/ContentColumn/Header/ActionHeader/ActionMargin/HeaderRow/WindowChrome",
		"Root/Body/Sidebar/SidebarColumn/NavMargin/NavList/StoreButton",
		"Root/Body/Sidebar/SidebarColumn/NavMargin/NavList/LibraryButton",
		"Root/Body/Sidebar/SidebarColumn/NavMargin/NavList/FriendsButton",
		"Root/Body/Sidebar/SidebarColumn/NavMargin/NavList/ProfileButton",
		"Root/Body/Sidebar/SidebarColumn/ProfilePanel/ProfileRow/SettingsButton",
		"Root/Body/ContentColumn/MainMargin/Pages/StorePage",
		"Root/Body/ContentColumn/MainMargin/Pages/FriendsPage",
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
	# Exercise dynamic store/library cards and scene-backed pages, not just the shell.
	for page_name in ["store", "library", "friends", "messages", "profile"]:
		main_scene.call("_navigate", page_name)
		await process_frame
		var page_node := main_scene.find_child("%sPage" % page_name.capitalize(), true, false)
		if page_node == null and page_name != "friends":
			_fail("missing page after navigation: %s" % page_name)
			return
	main_scene.call("_navigate", "store")
	await process_frame

	if main_scene.find_child("OnlineState", true, false) == null:
		_fail("presence label was not found")
		return
	if not _verify_activity_and_chat(main_scene, online):
		return
	if not _verify_scene_owned_ui(main_scene):
		return
	if int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")) != 1:
		_fail("project UI default must be linear")
		return
	var library := main_scene.find_child("LibraryPage", true, false)
	library.call("_set_view", true)
	if not _verify_texture_filters(main_scene):
		return
	library.call("_set_view", false)
	if not _verify_texture_filters(main_scene):
		return

	online.call("disconnect_server")
	if not _verify_quiet_retries():
		return
	print("PARDEX boot smoke passed: identity repair -> pages -> activity checkpoints -> chat reconnect -> quiet offline retries")
	quit(0)
