extends SceneTree

const D := preload("res://scripts/data/pardex_distribution.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("Distribution: " + message)


func _run() -> void:
	var entry := {"id":"ci_update_fixture", "title":"Test", "version":"1.0.0", "executable":"Game.exe",
		"package":{"url":"https://distribution.invalid/game.zip", "sha256":"a".repeat(64), "size":123}}
	var manifest := {"schema":1, "launcher":{}, "games":[entry]}
	expect(D.validate(manifest), "valid independent manifest")
	for url in ["http://example.com/file", "file:///tmp/file", "https://user@example.com/file"]:
		var bad := manifest.duplicate(true)
		bad["games"][0]["package"]["url"] = url
		expect(not D.validate(bad), "reject insecure package URL")
	for path in ["../outside.exe", "/root.exe", "C:/bad.exe", "folder/../bad.exe", "CON.exe", "Game.exe.", "a\\b.exe"]:
		expect(not D.safe_path(path), "reject unsafe Windows path")
	var duplicate := manifest.duplicate(true)
	duplicate["games"].append(entry)
	expect(not D.validate(duplicate), "reject duplicate game")
	var saved := D.manifest
	D.manifest = manifest
	expect(Catalog.game("ci_update_fixture").get("title", "") == "Test", "new remote game appears in catalog")
	expect(Catalog.action_label("ci_update_fixture") == "İndir", "new game download action")
	var archive := ProjectSettings.globalize_path("user://distribution-test.zip")
	var zip := ZIPPacker.new()
	expect(zip.open(archive) == OK, "create fixture zip")
	zip.start_file("Game.exe")
	zip.write_file("fixture-only-not-executable".to_utf8_buffer())
	zip.close_file()
	zip.close()
	var file := FileAccess.open(archive, FileAccess.READ)
	var metadata := {"url":"https://distribution.invalid/test.zip", "size":file.get_length(), "sha256":FileAccess.get_sha256(archive)}
	file.close()
	expect(D.verified_file(archive, metadata), "accept complete verified package")
	metadata["sha256"] = "0".repeat(64)
	expect(not D.verified_file(archive, metadata), "reject tampered package")
	metadata["size"] = 1
	expect(not D.verified_file(archive, metadata), "reject truncated package")
	expect(D.install_zip(archive, entry), "install verified fixture into version folder")
	var old := D.executable("ci_update_fixture")
	expect(not old.is_empty() and not D.needs_install("ci_update_fixture"), "activate installed version")
	var newer := entry.duplicate(true)
	newer["version"] = "1.1.0"
	newer["package"]["sha256"] = "b".repeat(64)
	D.manifest = {"schema":1, "games":[newer]}
	expect(Catalog.action_label("ci_update_fixture") == "Güncelle", "detect game update")
	zip.open(archive)
	zip.start_file("../Game.exe")
	zip.write_file("invalid".to_utf8_buffer())
	zip.close_file()
	zip.close()
	expect(not D.install_zip(archive, newer), "reject zip traversal")
	expect(D.executable("ci_update_fixture") == old and FileAccess.get_file_as_string(old) == "fixture-only-not-executable", "failed update preserves working version")
	zip.open(archive)
	zip.start_file("Game.exe")
	zip.write_file("new-fixture".to_utf8_buffer())
	zip.close_file()
	zip.close()
	expect(D.install_zip(archive, newer), "install second version")
	# Once the new version is active the previous folder is deleted (disk space).
	expect(D.executable("ci_update_fixture") != old and not FileAccess.file_exists(old) and not DirAccess.dir_exists_absolute(old.get_base_dir()), "remove previous version after activation")
	expect(FileAccess.get_file_as_string(D.executable("ci_update_fixture")) == "new-fixture", "new version active")

	# Store artwork and genres come from the catalog; nothing is borrowed from another game.
	var image := Image.create(8, 4, false, Image.FORMAT_RGB8)
	image.fill(Color(0.1, 0.6, 0.9))
	var png := ProjectSettings.globalize_path("user://distribution-test.png")
	image.save_png(png)
	var cover := {"url":"https://distribution.invalid/packages/%s.png" % FileAccess.get_sha256(png), "sha256":FileAccess.get_sha256(png), "size":FileAccess.get_file_as_bytes(png).size()}
	var styled := newer.duplicate(true)
	styled["cover"] = cover
	styled["genres"] = ["Bulmaca"]
	styled["players"] = "Tek oyunculu"
	expect(D.validate({"schema":1, "launcher":{}, "games":[styled]}), "accept cover and genres")
	for art in [{"url":"https://distribution.invalid/x.exe", "sha256":cover["sha256"], "size":10}, {"url":cover["url"], "sha256":cover["sha256"], "size":9000000}]:
		var bad_art := styled.duplicate(true)
		bad_art["banner"] = art
		expect(not D.validate({"schema":1, "launcher":{}, "games":[bad_art]}), "reject non-image or oversized artwork")
	var many := styled.duplicate(true)
	many["genres"] = ["a", "b", "c", "d", "e"]
	expect(not D.validate({"schema":1, "launcher":{}, "games":[many]}), "reject more than four genres")
	D.manifest = {"schema":1, "launcher":{}, "games":[styled]}
	var store := Catalog.game("ci_update_fixture")
	expect(store.get("genres") == ["Bulmaca"] and store.get("players") == "Tek oyunculu" and not str(store.get("cover", "")).begins_with("user://"), "clean store entry before art download")
	DirAccess.copy_absolute(png, ProjectSettings.globalize_path(D.art_download_path(cover)))
	store = Catalog.game("ci_update_fixture")
	expect(str(store.get("cover", "")).begins_with("user://art/") and Catalog.texture(str(store["cover"])) != null, "use downloaded cover")

	# Uninstall removes files and the install record.
	expect(D.uninstall("ci_update_fixture") and D.executable("ci_update_fixture").is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://games/ci_update_fixture")), "uninstall removes files and record")
	expect(Catalog.action_label("ci_update_fixture") == "İndir", "uninstalled game can be downloaded again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(D.art_download_path(cover)))
	DirAccess.remove_absolute(png)
	D.manifest = saved
	DirAccess.remove_absolute(archive)
	if failures == 0:
		print("DISTRIBUTION SMOKE PASSED: catalog, update, paths, atomic activation, old version cleanup, store art, uninstall")
	quit(0 if failures == 0 else 1)
